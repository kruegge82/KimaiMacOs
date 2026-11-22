import Foundation
import KimaiKit

/// Everything that changes data in Kimai.
extension AppModel {
    private static var busyError: KimaiError {
        .server(status: 0, message: L("Another change is still being saved. Try again in a moment."))
    }

    /// Runs one change at a time and makes sure the lists are reconciled afterwards — also
    /// after a failure, because a multi-step change may have succeeded partially.
    /// Returns `.cancelled` if another change is in flight (e.g. a double key press).
    private func perform(_ operation: (KimaiClient) async throws -> Void) async -> KimaiError? {
        guard let client else { return .invalidURL }
        guard !isWorking else { return .cancelled }
        guard canWrite else {
            return .server(status: 0, message: L(
                "The time zone of your Kimai profile is not known yet, so times cannot be saved reliably. Check the connection and try again."))
        }
        isWorking = true
        // Invalidates refreshes that started before this change: their snapshot of the
        // server is about to be outdated and must not overwrite what happens next.
        mutationCount += 1
        var failure: KimaiError?
        do {
            try await operation(client)
            actionProblem = nil
        } catch {
            failure = KimaiError.from(error)
        }
        mutationCount += 1
        isWorking = false
        updateMenuBarText()
        Task { await refresh() }
        return failure
    }

    // MARK: Timer

    /// Starts a timer and ends whatever was running before.
    @discardableResult
    func start(description: String, booking: Booking, tags: [String] = [], begin: Date? = nil) async -> Bool {
        let error = await startTimer(TimesheetDraft(
            begin: begin ?? Date(), projectID: booking.projectID, activityID: booking.activityID,
            description: description, tags: tags))
        present(error)
        return error == nil
    }

    private func startTimer(_ draft: TimesheetDraft) async -> KimaiError? {
        var draft = draft
        draft.end = nil
        let error = await perform { client in
            // What is running is asked from Kimai, not taken from the list on screen: a timer
            // that was stopped in the web UI a minute ago must not be touched again.
            let previous = try await self.runningTimers(client: client)
            let backdated = draft.begin < Date().addingTimeInterval(-30)
            // A new task cannot have begun before the one that is still running began: the
            // two records would overlap for the whole time. Nothing is changed in that case.
            if backdated, let conflict = previous.first(where: { draft.begin <= $0.begin }) {
                throw KimaiError.server(status: 0, message: L(
                    "The start you chose is before the running timer began (%@). Choose a later start, or stop the running timer first.",
                    Format.time(conflict.begin)))
            }
            // Normally the new timer is created first: if Kimai rejects it, the old one keeps
            // running and no time is lost. Only a server that forbids overlapping records
            // needs the old timer ended before a backdated one can be created.
            let stopFirst = backdated && !self.config.isAllowOverlapping
            var stoppedFirst: [Timesheet] = []
            if stopFirst {
                for entry in previous {
                    do {
                        let stopped = draft.begin > entry.begin
                            ? try await client.stop(id: entry.id, at: draft.begin)
                            : try await client.stop(id: entry.id)
                        self.applyStopped(stopped)
                        stoppedFirst.append(stopped)
                    } catch {
                        // The request may have reached Kimai even though the answer got lost.
                        // Find out, then make sure the old task keeps being tracked.
                        if let current = try? await client.timesheet(id: entry.id) {
                            if !current.isRunning {
                                self.applyStopped(current)
                                stoppedFirst.append(current)
                            }
                        } else {
                            self.notice = L(
                                "The connection failed while “%@” was being stopped. Check in Kimai whether it is still running.",
                                self.displayName(of: entry))
                        }
                        await self.restoreTracking(after: stoppedFirst, client: client)
                        throw error
                    }
                }
            }

            let created: Timesheet
            do {
                created = try await client.create(draft)
            } catch {
                // The old timer is already stopped but the new one was rejected.
                await self.restoreTracking(after: stoppedFirst, client: client)
                throw error
            }
            self.activeEntries = [created]
            self.reportDroppedTags(requested: draft.tags, saved: created)

            // From here on the new timer exists. Problems while tidying up the previous one
            // are reported separately and must not look like a failed start.
            do {
                try await self.endPredecessors(
                    stopFirst ? [] : previous, of: created, backdated: backdated, client: client)
            } catch {
                self.notice = L(
                    "The new timer is running, but the previous one could not be ended cleanly: %@ Please check its end time.",
                    ErrorText.message(for: KimaiError.from(error)))
            }
        }
        if error == nil {
            if let projectID = draft.projectID, let activityID = draft.activityID {
                let booking = Booking(projectID: projectID, activityID: activityID)
                preferences.remember(booking)
                draftBooking = booking
            }
            draftDescription = ""
        }
        return error
    }

    /// The timers that are running on the server right now. Brings the local list in line,
    /// so entries that were stopped elsewhere no longer count as running.
    private func runningTimers(client: KimaiClient) async throws -> [Timesheet] {
        let running = try await client.activeTimesheets().sorted { $0.begin > $1.begin }
        activeEntries = running
        return running
    }

    private func displayName(of entry: Timesheet) -> String {
        entry.trimmedDescription.isEmpty
            ? catalog.breadcrumb(projectID: entry.projectID, activityID: entry.activityID)
            : entry.trimmedDescription
    }

    /// Continues the tasks that were cut off for a switch that then failed, from where they
    /// were cut off, so no working time goes untracked. Says so if that is not possible.
    private func restoreTracking(after stopped: [Timesheet], client: KimaiClient) async {
        for entry in stopped {
            if let resumed = await resume(entry, client: client) {
                activeEntries = [resumed]
            } else {
                notice = L(
                    "Tracking is stopped: “%@” was ended at %@ and could not be continued automatically. Start it again to keep tracking.",
                    displayName(of: entry), Format.time(entry.end ?? Date()))
            }
        }
    }

    /// Starts a running record that continues `stopped` from its end, with the same booking,
    /// description, tags and billable flag.
    private func resume(_ stopped: Timesheet, client: KimaiClient) async -> Timesheet? {
        var continuation = TimesheetDraft(
            begin: stopped.end ?? Date(), projectID: stopped.projectID, activityID: stopped.activityID,
            description: stopped.description ?? "", tags: stopped.tags, billable: stopped.billable)
        if let resumed = try? await client.create(continuation) { return resumed }
        // Accounts that may not set "billable" get the request rejected; Kimai's own rule
        // then decides, which is the best that can be done for them.
        continuation.billable = nil
        return try? await client.create(continuation)
    }

    /// Ends the timers that ran before `created` at the moment the new one began, so the
    /// records neither overlap nor leave a gap.
    private func endPredecessors(
        _ previous: [Timesheet], of created: Timesheet, backdated: Bool, client: KimaiClient
    ) async throws {
        let stillActive = Set(try await client.activeTimesheets().map(\.id)).subtracting([created.id])
        for entry in previous {
            let cutoffIsValid = created.begin > entry.begin
            let isStillRunning = stillActive.contains(entry.id)
            if cutoffIsValid, config.allowsEditingTimes {
                if !isStillRunning {
                    // Kimai stopped it during the switch — or it was stopped earlier on another
                    // device. Its end is only pulled back to the new begin, never pushed out.
                    let current = try await client.timesheet(id: entry.id)
                    guard let end = current.end, end > created.begin else {
                        applyStopped(current)
                        continue
                    }
                }
                applyStopped(try await client.stop(id: entry.id, at: created.begin))
            } else if isStillRunning {
                // The new task began before the old one, or the server does not allow setting
                // times: all that can be done is to stop it now.
                applyStopped(try await client.stop(id: entry.id))
            }
        }
        // Timers started elsewhere in the meantime.
        for id in stillActive.subtracting(previous.map(\.id)) {
            applyStopped(try await client.stop(id: id))
        }
    }

    /// ⌘↩: stops the running timer, or starts one from what is entered in the timer bar.
    func toggleTimer() {
        if activeEntry != nil {
            Task { await stopActive() }
        } else if let booking = draftBooking {
            let description = draftDescription
            Task { await start(description: description, booking: booking) }
        } else {
            showMainWindow()
        }
    }

    /// Stops the running timer, optionally at a moment in the past. With `only`, nothing
    /// happens unless exactly that timer is still the one running — for confirmations that
    /// were shown a while ago.
    @discardableResult
    func stopActive(at end: Date? = nil, only expected: Timesheet? = nil) async -> Bool {
        func targets() -> [Timesheet] {
            guard let expected else { return activeEntries }
            return activeEntries.filter { $0.id == expected.id && $0.begin == expected.begin }
        }
        guard !targets().isEmpty else { return expected == nil }
        let error = await perform { client in
            // Only timers Kimai still reports as running are stopped; one that was already
            // ended elsewhere keeps the end it has.
            let running = Set(try await self.runningTimers(client: client).map(\.id))
            for entry in targets() where running.contains(entry.id) {
                let stopped: Timesheet
                if let end, end > entry.begin {
                    stopped = try await client.stop(id: entry.id, at: end)
                } else {
                    stopped = try await client.stop(id: entry.id)
                }
                self.applyStopped(stopped)
            }
        }
        present(error)
        return error == nil
    }

    /// Starts the same task again. If its project or activity is no longer bookable, the
    /// editor opens instead so nothing is booked on a silently substituted project.
    func restart(_ task: TaskTemplate) async {
        guard let booking = task.booking, catalog.isEmpty || catalog.isValid(booking) else {
            editor = EditorRequest(mode: .create(TimesheetDraft(
                begin: Date(), end: nil, projectID: nil, activityID: nil,
                description: task.description, tags: task.tags)))
            showMainWindow(focusDescription: false)
            return
        }
        await start(description: task.description, booking: booking, tags: task.tags)
    }

    func restart(_ entry: Timesheet) async {
        await restart(TaskTemplate(
            description: entry.trimmedDescription, projectID: entry.projectID, activityID: entry.activityID,
            tags: entry.tags, lastUsed: entry.begin, timesheetID: entry.id))
    }

    // MARK: Records
    // These return the error instead of showing it, so the editor can keep the user's input
    // and explain what Kimai rejected.

    /// Creates a record. A draft without end starts a running timer.
    func create(_ draft: TimesheetDraft) async -> KimaiError? {
        guard !isWorking else { return Self.busyError }
        if draft.end == nil {
            return await startTimer(draft)
        }
        let error = await perform { client in
            let created = try await client.create(draft)
            self.insertFinished(created)
            self.reportDroppedTags(requested: draft.tags, saved: created)
        }
        if error == nil, let projectID = draft.projectID, let activityID = draft.activityID {
            preferences.remember(Booking(projectID: projectID, activityID: activityID))
        }
        return error
    }

    /// Changes the given fields of a record and nothing else.
    func update(id: Int, changes: TimesheetChanges) async -> KimaiError? {
        guard !changes.isEmpty else { return nil }
        guard !isWorking else { return Self.busyError }
        let error = await perform { client in
            let updated = try await client.update(id: id, changes: changes)
            self.replace(updated)
            if let tags = changes.tags {
                self.reportDroppedTags(requested: tags, saved: updated)
            }
        }
        if error == nil, let booking = changes.booking {
            preferences.remember(booking)
        }
        return error
    }

    @discardableResult
    func delete(_ entry: Timesheet) async -> Bool {
        // Only records that are currently shown may be deleted; an id from an earlier
        // connection could belong to a different record now.
        guard (entries + activeEntries + weekEntries).contains(where: { $0.id == entry.id && $0.begin == entry.begin }) else {
            present(.notFound)
            return false
        }
        let error = await perform { client in
            try await client.delete(id: entry.id)
            self.activeEntries.removeAll { $0.id == entry.id }
            self.entries.removeAll { $0.id == entry.id }
            self.weekEntries.removeAll { $0.id == entry.id }
        }
        present(error)
        return error == nil
    }

    /// Opens the editor with a copy that still needs its times confirmed.
    func duplicate(_ entry: Timesheet) {
        let now = Date()
        var draft = TimesheetDraft(timesheet: entry)
        draft.begin = now.addingTimeInterval(-Double(max(entry.elapsed(at: now), 60)))
        draft.end = now
        draft.billable = nil
        editor = EditorRequest(mode: .create(draft))
    }

    func newEntry() {
        let now = Date()
        let begin = lastEndToday ?? now.addingTimeInterval(-3600)
        editor = EditorRequest(mode: .create(TimesheetDraft(
            begin: begin, end: now, projectID: draftBooking?.projectID,
            activityID: draftBooking?.activityID)))
    }

    func edit(_ entry: Timesheet) {
        editor = EditorRequest(mode: .edit(entry))
    }

    /// Kimai silently drops tags the account may not create. Saying so beats letting the
    /// user discover later that a tag is missing.
    private func reportDroppedTags(requested: [String], saved: Timesheet) {
        let kept = Set(saved.tags.map(Catalog.fold))
        let dropped = requested.filter { !kept.contains(Catalog.fold($0)) }
        notice = dropped.isEmpty
            ? nil
            : L(
                "Kimai did not save these tags: %@. Your account may only be allowed to use existing tags.",
                dropped.joined(separator: ", "))
    }

    // MARK: Local bookkeeping (optimistic updates until the next refresh)

    private func applyStopped(_ stopped: Timesheet) {
        activeEntries.removeAll { $0.id == stopped.id }
        insertFinished(stopped)
    }

    private func insertFinished(_ entry: Timesheet) {
        guard !entry.isRunning else {
            activeEntries = [entry] + activeEntries.filter { $0.id != entry.id }
            return
        }
        let newestFirst: (Timesheet, Timesheet) -> Bool = { ($0.begin, $0.id) > ($1.begin, $1.id) }
        if searchTerm == nil {
            entries = (entries.filter { $0.id != entry.id } + [entry]).sorted(by: newestFirst)
        }
        if entry.begin >= TimesheetGrouping.week(containing: Date()).start {
            weekEntries = (weekEntries.filter { $0.id != entry.id } + [entry]).sorted(by: newestFirst)
        }
    }

    private func replace(_ updated: Timesheet) {
        if updated.isRunning {
            activeEntries = activeEntries.map { $0.id == updated.id ? updated : $0 }
        } else {
            activeEntries.removeAll { $0.id == updated.id }
            entries = entries.map { $0.id == updated.id ? updated : $0 }
            weekEntries = weekEntries.map { $0.id == updated.id ? updated : $0 }
        }
    }

    // MARK: Connection

    /// Checks address and credentials without saving anything.
    func test(_ input: ConnectionInput) async -> Result<ConnectionSummary, KimaiError> {
        await probe(input).map(\.summary)
    }

    private func probe(_ input: ConnectionInput) async -> Result<(summary: ConnectionSummary, profile: KimaiUser), KimaiError> {
        guard let configuration = input.configuration else { return .failure(.invalidURL) }
        let probe = KimaiClient(configuration: configuration, transport: session)
        do {
            let version = try await probe.version()
            let profile = try await probe.currentUser()
            return .success((ConnectionSummary(version: version.version, userName: profile.displayName), profile))
        } catch {
            return .failure(KimaiError.from(error))
        }
    }

    /// Verifies the connection, then stores it (token in the Keychain) and loads the data.
    func connect(_ input: ConnectionInput) async -> Result<ConnectionSummary, KimaiError> {
        guard !isWorking else { return .failure(Self.busyError) }
        connectAttempt += 1
        let attempt = connectAttempt
        let result = await probe(input)
        guard case .success(let verified) = result, let configuration = input.configuration else {
            return result.map(\.summary)
        }
        // While the server was being checked the user may have disconnected, started another
        // attempt or begun a change; then this attempt must not store anything.
        guard attempt == connectAttempt else { return .failure(.cancelled) }
        guard !isWorking else { return .failure(Self.busyError) }
        do {
            try secrets.write(configuration.auth.token, account: Self.tokenAccount)
        } catch {
            return .failure(.server(status: 0, message: L("The API token could not be saved to the Keychain.")))
        }
        let address = configuration.baseURL.absoluteString
        if address != preferences.serverURL {
            // Project and activity ids of another installation mean nothing here.
            preferences.lastBooking = nil
            preferences.recentBookings = []
            draftBooking = nil
            cache.clear()
        }
        preferences.serverURL = address
        preferences.authMode = input.mode
        preferences.username = input.username.trimmingCharacters(in: .whitespacesAndNewlines)

        resetServerState()
        guard activateStoredConnection() else { return .failure(.invalidURL) }
        // The profile is already known from the check above, so its time zone applies from
        // the very first write.
        serverVersion = verified.summary.version
        apply(profile: verified.profile)
        phase = .loading
        startBackgroundRefresh()
        Task {
            await refresh(reloadCatalog: true)
        }
        return .success(verified.summary)
    }

    func disconnect() {
        guard !isWorking else { return }
        connectAttempt += 1
        secrets.delete(account: Self.tokenAccount)
        cache.clear()
        client = nil
        resetServerState()
        phase = .needsSetup
    }
}
