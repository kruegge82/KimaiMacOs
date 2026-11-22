import AppKit
import KimaiKit

/// Notices when the user was away while a timer kept running and asks what to do with that
/// time. Nothing is ever discarded without an explicit decision.
final class IdleMonitor {
    private weak var model: AppModel?
    private var timer: Timer?
    private var idleSince: Date?
    private var isPrompting = false
    private var observers: [NSObjectProtocol] = []

    func start(model: AppModel) {
        self.model = model
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // While the Mac sleeps there are no ticks, so remember when it went to sleep.
        let sleep = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.markIdleStart(Date()) }
        }
        observers = [sleep]
    }

    private var isEnabled: Bool {
        guard let model else { return false }
        return model.preferences.idleDetectionEnabled && model.activeEntry != nil
    }

    private var threshold: TimeInterval {
        Double(max(1, model?.preferences.idleMinutes ?? 10) * 60)
    }

    private func markIdleStart(_ date: Date) {
        guard isEnabled, idleSince == nil else { return }
        idleSince = date
    }

    private func secondsSinceLastInput() -> TimeInterval {
        // ~0 is kCGAnyInputEventType: any keyboard, mouse or trackpad activity.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func tick() {
        guard isEnabled else {
            idleSince = nil
            return
        }
        let idle = secondsSinceLastInput()
        if let since = idleSince {
            // The user touched the Mac again.
            guard idle < 5, !isPrompting else { return }
            idleSince = nil
            if Date().timeIntervalSince(since) >= threshold {
                prompt(idleSince: since)
            }
        } else if idle >= threshold {
            idleSince = Date().addingTimeInterval(-idle)
        }
    }

    private func prompt(idleSince: Date) {
        guard let model, let running = model.activeEntry, idleSince > running.begin else { return }
        isPrompting = true
        defer { isPrompting = false }

        let away = Format.spokenDuration(Int(Date().timeIntervalSince(idleSince)))
        let name = running.trimmedDescription.isEmpty
            ? model.catalog.breadcrumb(projectID: running.projectID, activityID: running.activityID)
            : running.trimmedDescription

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("You were away for %@", away)
        alert.informativeText = L(
            "The timer “%@” kept running since %@. What should happen with the time you were away?",
            name, Format.time(idleSince))
        alert.addButton(withTitle: L("Keep Time"))
        alert.addButton(withTitle: L("Stop Timer at %@", Format.time(idleSince)))
        alert.addButton(withTitle: L("Adjust…"))

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        // The dialog may have been open for a while; only the timer it asked about is stopped.
        case .alertSecondButtonReturn:
            Task { await model.stopActive(at: idleSince, only: running) }
        case .alertThirdButtonReturn:
            if let cutoff = askForCutoff(suggested: idleSince, running: running) {
                Task { await model.stopActive(at: cutoff, only: running) }
            }
        default:
            break
        }
    }

    /// Lets the user pick the moment they really stopped working. Cancelling keeps the time.
    private func askForCutoff(suggested: Date, running: Timesheet) -> Date? {
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.minDate = running.begin
        picker.maxDate = Date()
        picker.dateValue = suggested
        picker.setAccessibilityLabel(L("End of work"))

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("When did you stop working?")
        alert.informativeText = L("The timer is stopped at the time you choose. Cancel keeps the timer running.")
        alert.accessoryView = picker
        alert.addButton(withTitle: L("Stop Timer"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return min(max(picker.dateValue, running.begin.addingTimeInterval(60)), Date())
    }
}
