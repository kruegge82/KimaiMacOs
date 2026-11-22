import AppKit
import KimaiKit
import Observation

/// A failure worth telling the user about.
struct Problem: Identifiable, Equatable {
    let id = UUID()
    let error: KimaiError
    var message: String { ErrorText.message(for: error) }

    static func == (lhs: Problem, rhs: Problem) -> Bool { lhs.error == rhs.error }
}

/// Asks the main window to present the entry editor.
struct EditorRequest: Identifiable {
    enum Mode {
        /// New record. A draft without `end` starts a running timer.
        case create(TimesheetDraft)
        case edit(Timesheet)
    }

    let id = UUID()
    let mode: Mode
}

struct ConnectionSummary: Equatable {
    let version: String
    let userName: String
}

/// What the user types into the connection form.
struct ConnectionInput: Equatable {
    var url = ""
    var mode = AuthMode.bearer
    var username = ""
    var token = ""

    var configuration: ConnectionConfiguration? {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = ConnectionConfiguration.normalizedBaseURL(from: url), !token.isEmpty else { return nil }
        switch mode {
        case .bearer:
            return ConnectionConfiguration(baseURL: baseURL, auth: .bearer(token: token))
        case .legacy:
            guard !username.isEmpty else { return nil }
            return ConnectionConfiguration(baseURL: baseURL, auth: .legacy(username: username, token: token))
        }
    }
}

/// Single source of truth for everything the windows and the menu bar show.
@Observable
final class AppModel {
    enum Phase {
        case needsSetup
        case loading
        case ready
    }

    static let shared = AppModel()
    static let pageSize = 50
    static let tokenAccount = "api-token"

    let preferences: Preferences
    @ObservationIgnored let secrets: any SecretStore
    @ObservationIgnored let cache: CatalogCache
    @ObservationIgnored let session: any HTTPTransport
    @ObservationIgnored var client: KimaiClient?
    @ObservationIgnored var serverKey = ""

    // Connection
    var phase = Phase.needsSetup
    var serverVersion: String?
    var user: KimaiUser?
    var config = TimesheetConfig()

    // Data
    var catalog = Catalog.empty
    var activeEntries: [Timesheet] = []
    var entries: [Timesheet] = []
    var weekEntries: [Timesheet] = []
    var recentTasks: [TaskTemplate] = []
    var hasMoreEntries = false
    var isLoadingMore = false

    // Status
    var isRefreshing = false
    var isWorking = false
    var syncProblem: Problem?
    var actionProblem: Problem?
    /// Something that worked, but not quite as the user asked (e.g. tags Kimai dropped).
    var notice: String?
    var lastSync: Date?
    var menuBarText = ""

    // Interaction state shared by the main window and the menu bar panel
    var searchText = "" {
        didSet {
            guard oldValue != searchText else { return }
            // A different search is a different list: page requests of the old one must not
            // be appended to it.
            listGeneration += 1
            loadedPages = 1
            // "Load earlier" stays off until the first page of the new search is shown, so
            // pages of two different searches can never end up in one list.
            hasMoreEntries = false
            scheduleSearch()
        }
    }
    var draftDescription = ""
    var draftBooking: Booking?
    var editor: EditorRequest?
    /// Record whose deletion is waiting for confirmation.
    var pendingDelete: Timesheet?
    /// Incremented to ask the main window to focus the description field.
    var focusRequest = 0

    @ObservationIgnored var openMainWindowAction: (() -> Void)?
    @ObservationIgnored var loadedPages = 1
    @ObservationIgnored var listGeneration = 0
    @ObservationIgnored var mutationCount = 0
    @ObservationIgnored var connectionGeneration = 0
    /// Invalidates connection attempts that are still checking the server.
    @ObservationIgnored var connectAttempt = 0
    @ObservationIgnored private var refreshRequestedAgain = false
    @ObservationIgnored private var catalogReloadRequested = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var clockTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(
        preferences: Preferences = Preferences(),
        secrets: any SecretStore = KeychainStore(service: Bundle.main.bundleIdentifier ?? "app.kimaitimer.mac"),
        cache: CatalogCache = CatalogCache(),
        session: any HTTPTransport = URLSession.kimai()
    ) {
        self.preferences = preferences
        self.secrets = secrets
        self.cache = cache
        self.session = session
    }

    var isConfigured: Bool { client != nil }
    /// Times are written in the time zone of the Kimai profile, so nothing may be saved
    /// before that zone is known.
    var canWrite: Bool { client != nil && user?.timeZone != nil }
    var activeEntry: Timesheet? { activeEntries.first }
    var problem: Problem? { actionProblem ?? syncProblem }
    var searchTerm: String? {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? nil : term
    }

    // MARK: Lifecycle

    /// Called once at launch: restores the connection and starts background updates.
    func bootstrap() async {
        draftBooking = preferences.lastBooking
        startClock()
        guard activateStoredConnection() else {
            phase = .needsSetup
            return
        }
        phase = .loading
        startBackgroundRefresh()
        await refresh()
    }

    /// Builds the API client from the stored settings. Returns `false` if anything is missing.
    @discardableResult
    func activateStoredConnection() -> Bool {
        let input = storedConnection()
        guard let configuration = input.configuration else {
            client = nil
            return false
        }
        connectionGeneration += 1
        client = KimaiClient(configuration: configuration, transport: session)
        serverKey = configuration.baseURL.absoluteString
        if let cached = cache.load(server: serverKey) {
            catalog = cached
        }
        return true
    }

    func storedConnection() -> ConnectionInput {
        ConnectionInput(
            url: preferences.serverURL, mode: preferences.authMode, username: preferences.username,
            token: secrets.read(account: Self.tokenAccount) ?? "")
    }

    private func startClock() {
        clockTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMenuBarText() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    /// Safe to call repeatedly.
    func startBackgroundRefresh() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
        guard observers.isEmpty else { return }
        // Changes made in the Kimai web UI or on another device show up when the user comes back.
        let wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfStale(olderThan: 5) }
        }
        let activate = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfStale(olderThan: 20) }
        }
        observers = [wake, activate]
    }

    func refreshIfStale(olderThan seconds: TimeInterval) {
        guard isConfigured else { return }
        if let lastSync, Date().timeIntervalSince(lastSync) < seconds { return }
        Task { await refresh() }
    }

    func updateMenuBarText() {
        let text = activeEntry.map {
            DurationFormat.clock($0.elapsed(at: Date()), showSeconds: preferences.showSecondsInMenuBar)
        } ?? ""
        if text != menuBarText { menuBarText = text }
    }

    // MARK: Loading

    /// Reloads timers, records and totals. Calls that arrive while a refresh is running are
    /// coalesced into one follow-up run.
    func refresh(reloadCatalog: Bool = false) async {
        guard isConfigured else { return }
        if reloadCatalog { catalogReloadRequested = true }
        if isRefreshing {
            refreshRequestedAgain = true
            return
        }
        isRefreshing = true
        repeat {
            refreshRequestedAgain = false
            await performRefresh()
        } while refreshRequestedAgain && isConfigured
        isRefreshing = false
        if phase == .loading { phase = .ready }
    }

    private func performRefresh() async {
        // A change in flight makes any snapshot outdated before it arrives; the change
        // triggers its own refresh when it is done.
        guard let api = client, !isWorking else { return }
        let generation = connectionGeneration
        let mutations = mutationCount
        let term = searchTerm
        let pages = loadedPages
        let list = listGeneration
        do {
            if serverVersion == nil {
                // First contact: proves address and credentials.
                let version = try await api.version()
                guard generation == connectionGeneration else { return }
                serverVersion = version.version
            }

            // The profile is loaded every time: its time zone decides how times are written,
            // and the user may change it in Kimai while this app keeps running.
            let weekStart = TimesheetGrouping.week(containing: Date()).start
            async let profileRequest = api.currentUser()
            async let configRequest = api.timesheetConfig()
            async let activeRequest = api.activeTimesheets()
            async let listRequest = Self.loadPages(api, count: pages, term: term)
            async let weekRequest = Self.loadAll(api, since: weekStart)
            async let recentRequest = api.recentTimesheets(size: 30)
            let (profile, active, loaded, week) = try await (profileRequest, activeRequest, listRequest, weekRequest)
            let recent = (try? await recentRequest) ?? []
            let serverConfig = try? await configRequest

            guard generation == connectionGeneration else { return }
            if isWorking {
                // A change started while this was loading; it refreshes again when it is done.
                return
            }
            apply(profile: profile)
            if let serverConfig { config = serverConfig }
            guard mutations == mutationCount, list == listGeneration, pages == loadedPages else {
                // The user changed something while we were loading; these results are outdated.
                refreshRequestedAgain = true
                return
            }
            // The requests are separate snapshots: a timer stopped in between shows up in both.
            // The finished record is the newer truth.
            let finished = Set(loaded.items.map(\.id)).union(week.map(\.id))
            assign(\.activeEntries, active.filter { !finished.contains($0.id) }.sorted { $0.begin > $1.begin })
            assign(\.entries, loaded.items)
            hasMoreEntries = loaded.hasMore
            assign(\.weekEntries, week)
            assign(\.recentTasks, TaskSuggestions.recentTasks(from: recent + loaded.items, limit: 12))

            if catalogReloadRequested || catalog.isEmpty || catalog.isStale() {
                catalogReloadRequested = false
                let fresh = try await api.catalog()
                guard generation == connectionGeneration else { return }
                catalog = fresh
                cache.save(fresh, server: serverKey)
                if let booking = draftBooking, !fresh.isValid(booking) { draftBooking = nil }
            }
            syncProblem = nil
            lastSync = Date()
            updateMenuBarText()
        } catch {
            guard generation == connectionGeneration else { return }
            let kimaiError = KimaiError.from(error)
            if kimaiError != .cancelled, syncProblem?.error != kimaiError {
                syncProblem = Problem(error: kimaiError)
            }
        }
    }

    /// Avoids needless view updates when a background refresh brings nothing new.
    private func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    func apply(profile: KimaiUser) {
        if user != profile { user = profile }
        if let zone = profile.timeZone, client?.timeZone != zone { client?.timeZone = zone }
    }

    /// Loads the first `count` pages again, so records that were edited or deleted elsewhere
    /// disappear and the next "Load earlier" continues at the right offset.
    nonisolated private static func loadPages(
        _ api: KimaiClient, count: Int, term: String?
    ) async throws -> (items: [Timesheet], hasMore: Bool) {
        var items: [Timesheet] = []
        var seen = Set<Int>()
        var hasMore = false
        for page in 1...max(1, count) {
            let result = try await api.timesheets(page: page, size: pageSize, term: term)
            items += result.items.filter { seen.insert($0.id).inserted }
            hasMore = result.hasMore
            if !hasMore { break }
        }
        return (items, hasMore)
    }

    /// Every finished record since `start`, for totals that do not depend on what is listed.
    nonisolated private static func loadAll(_ api: KimaiClient, since start: Date) async throws -> [Timesheet] {
        var items: [Timesheet] = []
        var seen = Set<Int>()
        var page = 1
        while true {
            let result = try await api.timesheets(page: page, size: 500, begin: start)
            items += result.items.filter { seen.insert($0.id).inserted }
            // An empty page ends the loop even if a server keeps claiming there is more.
            if !result.hasMore || result.items.isEmpty { break }
            page += 1
        }
        return items
    }

    func loadMore() async {
        guard let client, hasMoreEntries, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let term = searchTerm
        let generation = connectionGeneration
        let list = listGeneration
        do {
            let page = try await client.timesheets(page: loadedPages + 1, size: Self.pageSize, term: term)
            guard list == listGeneration, generation == connectionGeneration else { return }
            let known = Set(entries.map(\.id))
            entries += page.items.filter { !known.contains($0.id) }
            loadedPages += 1
            hasMoreEntries = page.hasMore
        } catch {
            present(KimaiError.from(error))
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            await self.refresh()
        }
    }

    // MARK: Totals

    func todaySeconds(at now: Date = Date()) -> Int {
        TimesheetGrouping.total(
            of: weekEntries + activeEntries, in: TimesheetGrouping.day(containing: now), at: now)
    }

    func weekSeconds(at now: Date = Date()) -> Int {
        TimesheetGrouping.total(
            of: weekEntries + activeEntries, in: TimesheetGrouping.week(containing: now), at: now)
    }

    /// End of the most recent finished record of today, for "continue where I left off".
    var lastEndToday: Date? {
        weekEntries.compactMap(\.end).max().flatMap { Calendar.current.isDateInToday($0) ? $0 : nil }
    }

    // MARK: Helpers used by the actions

    func present(_ error: KimaiError?) {
        guard let error, error != .cancelled else { return }
        actionProblem = Problem(error: error)
    }

    func showMainWindow(focusDescription: Bool = true) {
        NSApp.activate(ignoringOtherApps: true)
        openMainWindowAction?()
        if focusDescription { focusRequest += 1 }
    }

    func openKimaiInBrowser() {
        guard let url = client?.configuration.baseURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Forgets everything that belongs to the current server.
    func resetServerState() {
        connectionGeneration += 1
        // An open editor or delete confirmation belongs to a record of the old server; acting
        // on it elsewhere could hit an unrelated record with the same id.
        editor = nil
        pendingDelete = nil
        user = nil
        serverVersion = nil
        config = TimesheetConfig()
        catalog = .empty
        activeEntries = []
        entries = []
        weekEntries = []
        recentTasks = []
        hasMoreEntries = false
        loadedPages = 1
        syncProblem = nil
        actionProblem = nil
        notice = nil
        lastSync = nil
        updateMenuBarText()
    }
}
