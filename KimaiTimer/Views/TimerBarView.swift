import KimaiKit
import SwiftUI

/// The place where timers are started, switched and stopped.
struct TimerBarView: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    @State private var showComposerWhileRunning = false
    @State private var showStartEarlier = false
    @State private var earlierBegin = Date()
    @State private var suggestionIndex: Int?
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let running = model.activeEntry {
                runningRow(running)
                if showComposerWhileRunning {
                    Divider()
                    composer(startTitle: L("Switch"))
                }
            } else {
                composer(startTitle: L("Start"))
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
        .onChange(of: model.focusRequest) {
            if model.activeEntry != nil { showComposerWhileRunning = true }
            descriptionFocused = true
        }
        .onChange(of: model.activeEntry?.id) {
            showComposerWhileRunning = false
        }
    }

    // MARK: Running

    private func runningRow(_ entry: Timesheet) -> some View {
        HStack(spacing: 12) {
            RunningIndicator()
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.trimmedDescription.isEmpty ? L("No description") : entry.trimmedDescription)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(entry.trimmedDescription.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Text(model.catalog.breadcrumb(projectID: entry.projectID, activityID: entry.activityID))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("Running timer"))
            Spacer(minLength: 12)
            ElapsedTimeText(entry: entry)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .help(L("Started at %@", Format.time(entry.begin)))
            // Titles are dropped in narrow windows so the description keeps its room.
            ViewThatFits(in: .horizontal) {
                secondaryActions(entry).labelStyle(.titleAndIcon)
                secondaryActions(entry).labelStyle(.iconOnly)
            }
            .layoutPriority(-1)
            Button {
                Task { await model.stopActive() }
            } label: {
                Label(L("Stop"), systemImage: "stop.fill")
                    .frame(minWidth: 64)
            }
            .controlSize(.large)
            .disabled(model.isWorking)
            .help(L("Stop the timer (⌘↩)"))
        }
        .labelStyle(.titleAndIcon)
    }

    private func secondaryActions(_ entry: Timesheet) -> some View {
        HStack(spacing: 8) {
            Button {
                model.edit(entry)
            } label: {
                Label(L("Edit"), systemImage: "pencil")
            }
            .help(L("Edit the running entry"))
            Button {
                showComposerWhileRunning.toggle()
                if showComposerWhileRunning { descriptionFocused = true }
            } label: {
                Label(L("Switch Task"), systemImage: "arrow.left.arrow.right")
            }
            .help(L("Stop this timer and start another task"))
        }
    }

    // MARK: Composer

    private var suggestions: [TaskTemplate] {
        guard descriptionFocused else { return [] }
        return TaskSuggestions.matching(
            model.draftDescription, in: model.recentTasks, catalog: model.catalog, limit: 4
        ).filter { task in
            // Offering exactly what is already entered would only be noise.
            !(task.description == model.draftDescription && task.booking == model.draftBooking)
        }
    }

    private func composer(startTitle: String) -> some View {
        @Bindable var model = model
        let suggestions = suggestions
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L("What are you working on?"), text: $model.draftDescription)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($descriptionFocused)
                    .onSubmit { submit(suggestions: suggestions) }
                    .onKeyPress(.downArrow) {
                        guard !suggestions.isEmpty else { return .ignored }
                        suggestionIndex = min((suggestionIndex ?? -1) + 1, suggestions.count - 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard let index = suggestionIndex else { return .ignored }
                        suggestionIndex = index > 0 ? index - 1 : nil
                        return .handled
                    }
                    .onChange(of: model.draftDescription) { suggestionIndex = nil }
                    .accessibilityLabel(L("Description"))
                BookingPickerButton(booking: $model.draftBooking, isPresented: $showPicker)
                    .frame(width: 260)
                startButton(title: startTitle)
            }
            if !suggestions.isEmpty {
                suggestionList(suggestions)
            }
        }
    }

    private func startButton(title: String) -> some View {
        // A real prominent button plus a separate options menu: a split `Menu` does not
        // take the prominent style, and Start is the most important control here.
        HStack(spacing: 4) {
            Button {
                start(begin: nil)
            } label: {
                Label(title, systemImage: "play.fill")
                    .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .help(L("Start the timer (↩)"))
            Menu {
                // Only offered when it cannot collide with a timer that is still running.
                if let lastEnd = model.lastEndToday, model.activeEntries.allSatisfy({ $0.begin < lastEnd }) {
                    Button(L("Start at End of Last Entry (%@)", Format.time(lastEnd))) {
                        start(begin: lastEnd)
                    }
                }
                Button(L("Start Earlier…")) {
                    let proposal = Date().addingTimeInterval(-15 * 60)
                    // Never propose a start before the running timer began.
                    earlierBegin = max(proposal, model.activeEntry.map { $0.begin.addingTimeInterval(60) } ?? proposal)
                    showStartEarlier = true
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("More ways to start"))
            .accessibilityLabel(L("More ways to start"))
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.large)
        .disabled(model.isWorking)
        .popover(isPresented: $showStartEarlier, arrowEdge: .bottom) {
            StartEarlierView(begin: $earlierBegin, runningEntry: model.activeEntry) {
                showStartEarlier = false
                start(begin: earlierBegin)
            }
        }
    }

    private func suggestionList(_ suggestions: [TaskTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, task in
                Button {
                    apply(task)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text(task.description)
                            .lineLimit(1)
                        Text(model.catalog.breadcrumb(projectID: task.projectID, activityID: task.activityID))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        index == suggestionIndex ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(L("Fills in this task"))
            }
        }
        .font(.callout)
    }

    private func apply(_ task: TaskTemplate) {
        model.draftDescription = task.description
        // If the task's project is no longer bookable, the booking is cleared rather than
        // left on whatever was selected before: the user has to choose deliberately.
        model.draftBooking = task.booking.flatMap { model.catalog.isValid($0) ? $0 : nil }
        suggestionIndex = nil
        descriptionFocused = true
    }

    private func submit(suggestions: [TaskTemplate]) {
        if let index = suggestionIndex, suggestions.indices.contains(index) {
            apply(suggestions[index])
        } else {
            start(begin: nil)
        }
    }

    private func start(begin: Date?) {
        guard let booking = model.draftBooking else {
            // Kimai needs a project and an activity; ask for them instead of failing.
            showPicker = true
            return
        }
        let description = model.draftDescription
        Task { await model.start(description: description, booking: booking, begin: begin) }
    }
}

/// Lets the user say when a task really started.
struct StartEarlierView: View {
    @Binding var begin: Date
    let runningEntry: Timesheet?
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("When did you start?"))
                .font(.headline)
            DatePicker(L("Start"), selection: $begin, in: ...Date(), displayedComponents: [.hourAndMinute])
                .datePickerStyle(.stepperField)
            HStack(spacing: 6) {
                ForEach([5, 15, 30, 60], id: \.self) { minutes in
                    Button(L("%d min ago", minutes)) {
                        begin = Date().addingTimeInterval(Double(-minutes * 60))
                    }
                }
            }
            .controlSize(.small)
            if let runningEntry, begin > runningEntry.begin {
                Label(
                    L("The running timer will be stopped at %@.", Format.time(begin)),
                    systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let runningEntry {
                Label(
                    L("Choose a time after %@, when the running timer began.", Format.time(runningEntry.begin)),
                    systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L("Start at %@", Format.time(begin)), action: onStart)
                    .keyboardShortcut(.defaultAction)
                    .disabled(runningEntry.map { begin <= $0.begin } ?? false)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
