import KimaiKit
import SwiftUI

/// What the menu bar shows: an icon, plus the elapsed time while a timer runs.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.activeEntry == nil ? "timer" : "record.circle")
            if !model.menuBarText.isEmpty {
                Text(model.menuBarText)
                    .monospacedDigit()
            }
        }
        .onAppear {
            if model.openMainWindowAction == nil {
                model.openMainWindowAction = { openWindow(id: "main") }
            }
        }
        .accessibilityLabel(model.activeEntry == nil ? L("Kimai Timer, no timer running") : L("Kimai Timer, timer running"))
    }
}

/// Panel behind the menu bar item: stop, start, switch and restart without opening a window.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var showPicker = false
    @State private var showSwitch = false
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.phase == .needsSetup {
                setupPrompt
            } else {
                if let problem = model.problem {
                    Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notice = model.notice {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Label(notice, systemImage: "info.circle.fill")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button(L("Dismiss")) { model.notice = nil }
                            .controlSize(.small)
                    }
                }
                if let running = model.activeEntry {
                    runningCard(running)
                }
                if model.activeEntry == nil || showSwitch {
                    quickStart
                }
                if showPicker {
                    @Bindable var model = model
                    BookingPickerList(booking: $model.draftBooking) { showPicker = false }
                        .frame(height: 280)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    recentTasks
                }
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            model.openMainWindowAction = { openWindow(id: "main") }
            model.refreshIfStale(olderThan: 20)
        }
        .onChange(of: model.activeEntry?.id) { showSwitch = false }
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack {
                Text(L("Today"))
                    .foregroundStyle(.secondary)
                Text(DurationFormat.clock(model.todaySeconds(at: context.date)))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                } else if let lastSync = model.lastSync {
                    Text(L("Synced %@", Format.time(lastSync)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Connect Kimai Timer to your Kimai server to start tracking."))
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Set Up Connection…")) { model.showMainWindow(focusDescription: false) }
                .buttonStyle(.borderedProminent)
        }
    }

    private func runningCard(_ entry: Timesheet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                RunningIndicator()
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.trimmedDescription.isEmpty ? L("No description") : entry.trimmedDescription)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    Text(model.catalog.breadcrumb(projectID: entry.projectID, activityID: entry.activityID))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                ElapsedTimeText(entry: entry)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
            }
            HStack {
                Button {
                    Task { await model.stopActive() }
                } label: {
                    Label(L("Stop"), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.isWorking)
                Button {
                    showSwitch.toggle()
                    if showSwitch { descriptionFocused = true }
                } label: {
                    Label(L("Switch…"), systemImage: "arrow.left.arrow.right")
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .accessibilityLabel(L("Switch Task"))
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var quickStart: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            TextField(L("What are you working on?"), text: $model.draftDescription)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($descriptionFocused)
                .onSubmit(start)
                .accessibilityLabel(L("Description"))
            HStack(spacing: 8) {
                Button {
                    showPicker.toggle()
                } label: {
                    BookingLabel(option: model.catalog.option(for: model.draftBooking))
                }
                .help(L("Choose project and activity"))
                Button(action: start) {
                    Label(model.activeEntry == nil ? L("Start") : L("Switch"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking)
            }
            .controlSize(.large)
        }
        .onAppear {
            if model.activeEntry == nil { descriptionFocused = true }
        }
    }

    @ViewBuilder
    private var recentTasks: some View {
        let tasks = model.recentTasks.prefix(5)
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Recent Tasks"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(tasks) { task in
                    RecentTaskRow(task: task)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(L("Open Kimai Timer")) { model.showMainWindow() }
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help(L("Settings"))
            .accessibilityLabel(L("Settings"))
            Button(L("Quit")) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }

    private func start() {
        guard let booking = model.draftBooking else {
            showPicker = true
            return
        }
        let description = model.draftDescription
        Task { await model.start(description: description, booking: booking) }
    }
}

private struct RecentTaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskTemplate
    @State private var isHovered = false

    var body: some View {
        Button {
            Task { await model.restart(task) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.activeEntry == nil ? "play.fill" : "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(isHovered ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.description.isEmpty ? L("No description") : task.description)
                        .lineLimit(1)
                    // Project and activity decide where time is booked, so they win over the
                    // customer name when space is tight; the full path is in the tooltip.
                    Text(shortBooking)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(model.isWorking)
        .help(fullBooking)
        .accessibilityLabel([task.description.isEmpty ? L("No description") : task.description, fullBooking]
            .joined(separator: ", "))
        .accessibilityHint(RestartWording.help(isRunning: model.activeEntry != nil))
    }

    private var fullBooking: String {
        model.catalog.breadcrumb(projectID: task.projectID, activityID: task.activityID)
    }

    private var shortBooking: String {
        let parts = [model.catalog.project(id: task.projectID)?.name, model.catalog.activity(id: task.activityID)?.name]
            .compactMap { $0 }
        return parts.isEmpty ? L("No project") : parts.joined(separator: " › ")
    }
}
