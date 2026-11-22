import KimaiKit
import SwiftUI

/// Small red dot that signals a running timer. Pulses unless Reduce Motion is on.
struct RunningIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 10, height: 10)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Elapsed time of a running record, updated every second without re-rendering the parent.
struct ElapsedTimeText: View {
    let entry: Timesheet
    var showSeconds = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(DurationFormat.clock(entry.elapsed(at: context.date), showSeconds: showSeconds))
                .monospacedDigit()
                .accessibilityLabel(L("Elapsed time"))
                .accessibilityValue(Format.spokenDuration(entry.elapsed(at: context.date)))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// Explains a failed sync or action and offers the next step.
struct ProblemBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let problem: Problem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: problem.error == .offline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if model.actionProblem != nil {
                    Text(L("That did not work."))
                        .fontWeight(.semibold)
                }
                Text(problem.message)
                    .fixedSize(horizontal: false, vertical: true)
                if model.actionProblem == nil, let lastSync = model.lastSync {
                    Text(L("Showing data from %@.", Format.time(lastSync)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if problem.error == .unauthorized || problem.error == .invalidResponse {
                Button(L("Open Settings")) {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
            }
            if model.actionProblem != nil {
                Button(L("Dismiss")) { model.actionProblem = nil }
            } else {
                Button(L("Check Connection")) {
                    Task { await model.refresh() }
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

/// Tells the user about something that succeeded only partially.
struct NoticeBanner: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("Dismiss"), action: onDismiss)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Button that records a global keyboard shortcut.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(isRecording ? L("Press shortcut…") : (shortcut?.display ?? L("Record Shortcut"))) {
                isRecording ? stopRecording() : startRecording()
            }
            .accessibilityLabel(L("Global shortcut"))
            .accessibilityValue(shortcut?.display ?? L("None"))
            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(L("Remove shortcut"))
                .accessibilityLabel(L("Remove shortcut"))
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
                stopRecording()
                return nil
            }
            guard let recorded = Shortcut(event: event) else {
                NSSound.beep()
                return nil
            }
            shortcut = recorded
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
