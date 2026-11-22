#if DEBUG
import Foundation
import KimaiKit

/// Development-only end-to-end check: `KimaiTimer --smoke-demo` drives the real `AppModel`
/// against the public Kimai demo (https://demo.kimai.org) — connect, load, start, switch,
/// stop, edit, search, delete — and prints one line per expectation. Nothing touches the
/// Keychain or the app's own settings.
struct SmokeTest {
    private var failures = 0

    private mutating func expect(_ condition: Bool, _ what: String) {
        if !condition { failures += 1 }
        print("\(condition ? "PASS" : "FAIL")  \(what)")
    }

    private func settle(_ model: AppModel, timeout: TimeInterval = 20, until done: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        // Give the refresh that follows every change a moment to begin.
        try? await Task.sleep(for: .milliseconds(400))
        while Date() < deadline {
            if !model.isRefreshing, !model.isWorking, done() { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    mutating func run() async -> Int32 {
        let suite = "app.kimaitimer.mac.smoke"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let model = AppModel(
            preferences: Preferences(defaults: defaults), secrets: MemorySecretStore(),
            cache: CatalogCache(fileName: "smoke-catalog.json"))

        // Editor logic (no network): records carry seconds the form does not show.
        do {
            let begin = Date(timeIntervalSinceReferenceDate: 800_000_000 + 30)   // hh:mm:30
            let record = Timesheet(
                id: 1, begin: begin, end: begin.addingTimeInterval(3640), duration: 3640,
                projectID: 1, activityID: 1, description: "Original")
            let form = EditorModel(request: EditorRequest(mode: .edit(record)))
            form.description = "Changed"
            form.commitDuration()
            expect(form.changes() == TimesheetChanges(description: "Changed"),
                   "description-only edit leaves times untouched")
            expect(form.validationMessage == nil, "untouched form is valid")

            let typed = EditorModel(request: EditorRequest(mode: .edit(record)))
            typed.durationText = "1:00:10"
            typed.commitDuration()
            // 3610 s from the exact start lands on the minute the form already displays;
            // it must still be saved because the user asked for it.
            expect(typed.changes() == TimesheetChanges(end: begin.addingTimeInterval(3610)),
                   "typed duration is saved even if the displayed end stays the same")

            let short = Timesheet(id: 2, begin: begin, end: begin.addingTimeInterval(20), duration: 20, projectID: 1, activityID: 1)
            let shortForm = EditorModel(request: EditorRequest(mode: .edit(short)))
            shortForm.tagsText = "x"
            shortForm.commitDuration()
            expect(shortForm.validationMessage == nil && shortForm.changes() == TimesheetChanges(tags: ["x"]),
                   "records shorter than a minute can still be edited")
        }

        // Wrong credentials must be reported, not stored.
        let rejected = await model.connect(ConnectionInput(url: "demo.kimai.org", mode: .bearer, token: "wrong"))
        expect(rejected == .failure(.unauthorized), "wrong token is rejected as unauthorized")
        expect(!model.isConfigured, "nothing is stored after a failed connect")

        let connected = await model.connect(ConnectionInput(url: "demo.kimai.org/api", mode: .bearer, token: "token_user"))
        guard case .success(let summary) = connected else {
            expect(false, "connect to demo: \(connected)")
            return 1
        }
        print("      Kimai \(summary.version) as \(summary.userName)")
        await settle(model) { model.phase == .ready && !model.catalog.isEmpty }
        expect(model.phase == .ready, "model becomes ready")
        expect(model.preferences.serverURL == "https://demo.kimai.org", "address is normalised")
        expect(!model.catalog.projects.isEmpty && !model.catalog.activities.isEmpty, "catalog loaded")
        expect(!model.entries.isEmpty, "first page of entries loaded (\(model.entries.count))")
        expect(model.user?.timeZone != nil, "profile time zone known (\(model.user?.timezone ?? "-"))")
        expect(model.syncProblem == nil, "no sync problem")

        let before = model.entries.count
        await model.loadMore()
        expect(model.entries.count > before, "load earlier adds entries (\(before) → \(model.entries.count))")
        expect(Set(model.entries.map(\.id)).count == model.entries.count, "no duplicates after paging")

        guard let project = model.catalog.projectGroups.first?.projects.first,
              let activity = model.catalog.activities(forProjectID: project.id).first
        else {
            expect(false, "a bookable project exists")
            return 1
        }
        let booking = Booking(projectID: project.id, activityID: activity.id)
        let marker = "KimaiTimer smoke \(Int(Date().timeIntervalSince1970))"

        model.draftDescription = "typed text"
        let started = await model.start(
            description: marker + " A", booking: booking, tags: [], begin: Date().addingTimeInterval(-600))
        expect(started, "timer starts")
        expect(model.activeEntry?.trimmedDescription == marker + " A", "running entry is shown immediately")
        expect(model.draftDescription.isEmpty, "draft is cleared after start")
        expect(model.preferences.lastBooking == booking, "booking is remembered")
        let firstID = model.activeEntry?.id
        await settle(model) { model.activeEntry?.id == firstID }
        expect(model.activeEntries.count == 1 && model.activeEntry?.id == firstID, "still running after refresh")
        model.updateMenuBarText()
        expect(!model.menuBarText.isEmpty, "menu bar shows elapsed time (\(model.menuBarText))")

        // Edit the running entry: must not stop it.
        if let running = model.activeEntry {
            let form = EditorModel(request: EditorRequest(mode: .edit(running)))
            form.description = marker + " A edited"
            // "Adams" exists on the demo; the demo user may not create new tags.
            form.tagsText = "Adams, zz-kimaitimer-unknown"
            expect(form.validationMessage == nil, "editor form is valid")
            let changes = form.changes()
            expect(changes.begin == nil && changes.end == nil && changes.booking == nil && changes.billable == nil,
                   "only description and tags are sent")
            let error = await model.update(id: running.id, changes: changes)
            expect(error == nil, "running entry can be edited \(error.map { ErrorText.message(for: $0) } ?? "")")
            expect(model.activeEntry?.tags == ["Adams"], "existing tag is saved (\(model.activeEntry?.tags ?? []))")
            expect(model.notice?.contains("zz-kimaitimer-unknown") == true, "dropped tag is reported")
            expect(model.activeEntry?.isRunning == true, "editing does not stop the timer")
            expect(model.activeEntry?.trimmedDescription == marker + " A edited", "edit is visible")
        }

        // A switch that claims to have begun before the running timer began would overlap
        // with it completely; it must be refused without touching anything.
        let runningBefore = model.activeEntry
        let refused = await model.start(
            description: marker + " X", booking: booking, begin: Date().addingTimeInterval(-3600))
        expect(!refused, "switch starting before the running timer is refused")
        expect(model.actionProblem != nil, "the refusal is explained")
        await settle(model) { model.activeEntry != nil }
        expect(model.activeEntry?.id == runningBefore?.id && model.activeEntries.count == 1, "the running timer is untouched")
        expect(!model.entries.contains { $0.trimmedDescription == marker + " X" }, "nothing was created")
        model.actionProblem = nil

        // Switch to another task that "started 2 minutes ago".
        let switchAt = Date().addingTimeInterval(-120)
        try? await Task.sleep(for: .seconds(1))
        let switched = await model.start(description: marker + " B", booking: booking, begin: switchAt)
        expect(switched, "switching starts the second timer")
        expect(model.activeEntries.count == 1 && model.activeEntry?.trimmedDescription == marker + " B", "only the new timer runs")
        await settle(model) { model.entries.contains { $0.id == firstID } }
        let first = model.entries.first { $0.id == firstID }
        expect(first != nil && first?.isRunning == false, "first timer is stopped and listed")
        if let end = first?.end {
            expect(abs(end.timeIntervalSince(switchAt)) < 61, "first timer ends where the second begins (no overlap, no gap)")
        }
        expect(model.notice == nil, "no clean-up problem reported \(model.notice ?? "")")
        if let begin = model.activeEntry?.begin {
            expect(abs(begin.timeIntervalSince(switchAt)) < 61, "backdated start is honoured")
        }
        expect(model.todaySeconds() > 0, "today's total counts the running timer")

        // A second action while one is in flight must be dropped, not run in parallel.
        async let firstStop = model.stopActive()
        async let secondStop = model.stopActive()
        _ = await (firstStop, secondStop)
        await settle(model) { model.activeEntries.isEmpty }
        expect(model.activeEntries.isEmpty, "double stop leaves a consistent state")
        let plainSwitchA = await model.start(description: marker + " C", booking: booking)
        let idC = model.activeEntry?.id
        let plainSwitchB = await model.start(description: marker + " D", booking: booking)
        await settle(model) { model.activeEntries.count == 1 }
        expect(plainSwitchA && plainSwitchB, "plain switch works")
        expect(model.activeEntries.count == 1 && model.activeEntry?.id != idC, "previous timer was ended by the switch")
        expect(model.entries.first { $0.id == idC }?.isRunning == false, "switched-away timer is listed as finished")

        let stopped = await model.stopActive()
        expect(stopped && model.activeEntry == nil, "timer stops")
        await settle(model) { model.activeEntries.isEmpty }
        let ours = model.entries.filter { $0.trimmedDescription.hasPrefix(marker) }
        expect(ours.count == 4, "all four entries are in the list (\(ours.count))")
        expect(model.recentTasks.contains { $0.description == marker + " B" }, "task appears in recent tasks")

        // Server-side validation error must come back as a readable message.
        if let entry = ours.first {
            let error = await model.update(
                id: entry.id, changes: TimesheetChanges(end: entry.begin.addingTimeInterval(-3600)))
            if case .validation = error {
                expect(true, "Kimai's validation error is surfaced: \(ErrorText.message(for: error!))")
            } else {
                expect(false, "end before begin is rejected (got \(String(describing: error)))")
            }
        }

        // Correct a finished entry by typing a duration, as a user would.
        if let entry = ours.last {
            let form = EditorModel(request: EditorRequest(mode: .edit(entry)))
            form.durationText = "1h 30m"
            form.commitDuration()
            expect(form.durationSeconds == 5400, "typed duration moves the end")
            expect(form.changes() == TimesheetChanges(end: entry.begin.addingTimeInterval(5400)),
                   "only the end is sent, measured from the exact start")
            let error = await model.update(id: entry.id, changes: form.changes())
            expect(error == nil, "finished entry can be corrected \(error.map { ErrorText.message(for: $0) } ?? "")")
            let saved = model.entries.first { $0.id == entry.id }
            expect(saved?.duration == 5400, "Kimai stored the new duration (\(saved?.duration ?? -1))")
        }

        model.searchText = marker
        try? await Task.sleep(for: .milliseconds(600))
        await settle(model) { model.entries.allSatisfy { $0.trimmedDescription.hasPrefix(marker) } }
        expect(model.entries.count == 4, "search finds exactly our entries (\(model.entries.count))")
        model.searchText = ""
        try? await Task.sleep(for: .milliseconds(600))
        await settle(model) { model.entries.count > 4 }

        for entry in ours {
            let deleted = await model.delete(entry)
            expect(deleted, "entry \(entry.id) deleted")
        }
        await settle(model) { !model.entries.contains { $0.trimmedDescription.hasPrefix(marker) } }
        expect(!model.entries.contains { $0.trimmedDescription.hasPrefix(marker) }, "deleted entries are gone")
        expect(model.actionProblem == nil, "no action error left over")

        model.disconnect()
        expect(model.phase == .needsSetup && !model.isConfigured, "disconnect returns to setup")
        defaults.removePersistentDomain(forName: suite)
        print(failures == 0 ? "SMOKE OK" : "SMOKE FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }
}
#endif
