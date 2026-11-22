import KimaiKit
import SwiftUI

/// Column metrics shared by rows and day headers so totals line up with durations.
enum EntryRowMetrics {
    static let durationWidth: CGFloat = 48
    static let actionSize: CGFloat = 28
    static let spacing: CGFloat = 10
    /// Width of the restart and "more" buttons including the gaps before them.
    static let actionsWidth = 2 * (actionSize + spacing)
}

struct DayHeaderView: View {
    let section: DaySection
    /// `false` while older records of this day may not be loaded yet.
    let isComplete: Bool
    /// Running timers that began on this day; they count towards its total.
    var running: [Timesheet] = []

    var body: some View {
        HStack {
            Text(Format.dayTitle(section.day))
            Spacer()
            if isComplete {
                if running.isEmpty {
                    total(at: Date())
                } else {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        total(at: context.date)
                    }
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
        // Section headers sit 8 pt further in than rows in an inset list.
        .padding(.trailing, EntryRowMetrics.actionsWidth - 8)
    }

    private func total(at now: Date) -> some View {
        let seconds = section.totalSeconds(at: now) + running.reduce(0) { $0 + $1.elapsed(at: now) }
        return Text(DurationFormat.clock(seconds))
            .monospacedDigit()
            .frame(minWidth: EntryRowMetrics.durationWidth, alignment: .trailing)
            .accessibilityLabel(L("Total"))
            .accessibilityValue(Format.spokenDuration(seconds))
    }
}

struct EntryRowView: View {
    @Environment(AppModel.self) private var model
    let entry: Timesheet
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: EntryRowMetrics.spacing) {
            Circle()
                .fill(model.catalog.color(forProjectID: entry.projectID))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.trimmedDescription.isEmpty ? L("No description") : entry.trimmedDescription)
                    .foregroundStyle(entry.trimmedDescription.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.catalog.breadcrumb(projectID: entry.projectID, activityID: entry.activityID))
                        .lineLimit(1)
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .lineLimit(1)
                    }
                    if entry.exported {
                        Image(systemName: "lock.fill")
                            .help(L("Exported – Kimai may not allow changes"))
                            .accessibilityLabel(L("Exported"))
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(Format.timeRange(begin: entry.begin, end: entry.end))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            Text(DurationFormat.clock(entry.elapsed()))
                .monospacedDigit()
                .frame(minWidth: EntryRowMetrics.durationWidth, alignment: .trailing)
            Button {
                Task { await model.restart(entry) }
            } label: {
                // Restarting while a timer runs is a switch: say so before the click.
                Image(systemName: model.activeEntry == nil ? "play.fill" : "arrow.left.arrow.right")
                    .frame(width: EntryRowMetrics.actionSize, height: EntryRowMetrics.actionSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(model.isWorking)
            .help(RestartWording.help(isRunning: model.activeEntry != nil))
            .accessibilityLabel(RestartWording.title(isRunning: model.activeEntry != nil))
            .accessibilityHint(RestartWording.help(isRunning: model.activeEntry != nil))
            Menu {
                EntryActions(entry: entry, onDelete: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: EntryRowMetrics.actionSize, height: EntryRowMetrics.actionSize)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L("More actions"))
            .accessibilityLabel(L("More actions"))
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        [
            entry.trimmedDescription.isEmpty ? L("No description") : entry.trimmedDescription,
            model.catalog.breadcrumb(projectID: entry.projectID, activityID: entry.activityID),
            Format.spokenDuration(entry.elapsed())
        ].joined(separator: ", ")
    }
}

/// Starting an old task again means switching when a timer is already running.
enum RestartWording {
    static func title(isRunning: Bool) -> String {
        isRunning ? L("Switch to This Task") : L("Start This Task Again")
    }

    static func help(isRunning: Bool) -> String {
        isRunning ? L("Stops the running timer and starts this task") : L("Starts a timer for this task")
    }
}

/// Shared by the row's "more" menu and the context menu.
struct EntryActions: View {
    @Environment(AppModel.self) private var model
    let entry: Timesheet
    var onDelete: () -> Void

    var body: some View {
        Button {
            Task { await model.restart(entry) }
        } label: {
            Label(
                RestartWording.title(isRunning: model.activeEntry != nil),
                systemImage: model.activeEntry == nil ? "play" : "arrow.left.arrow.right")
        }
        Button {
            model.edit(entry)
        } label: {
            Label(L("Edit…"), systemImage: "pencil")
        }
        Button {
            model.duplicate(entry)
        } label: {
            Label(L("Duplicate…"), systemImage: "plus.square.on.square")
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label(L("Delete…"), systemImage: "trash")
        }
    }
}
