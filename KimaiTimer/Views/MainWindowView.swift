import KimaiKit
import SwiftUI

struct MainWindowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var selection = Set<Timesheet.ID>()

    var body: some View {
        @Bindable var model = model
        Group {
            if model.phase == .needsSetup {
                WelcomeView()
            } else {
                content
                    .searchable(text: $model.searchText, placement: .toolbar, prompt: Text(L("Search entries")))
                    .toolbar { toolbar }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            model.openMainWindowAction = { openWindow(id: "main") }
        }
        .sheet(item: $model.editor) { request in
            EntryEditorView(request: request)
        }
        .confirmationDialog(
            L("Delete this entry?"),
            isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }),
            presenting: model.pendingDelete
        ) { entry in
            Button(L("Delete"), role: .destructive) {
                Task { await model.delete(entry) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: { entry in
            Text(L(
                "“%@” (%@) will be removed from Kimai. This cannot be undone.",
                entry.trimmedDescription.isEmpty
                    ? model.catalog.breadcrumb(projectID: entry.projectID, activityID: entry.activityID)
                    : entry.trimmedDescription,
                DurationFormat.clock(entry.elapsed())))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.newEntry()
            } label: {
                Label(L("New Entry"), systemImage: "plus")
            }
            .help(L("Add a finished entry (⌘N)"))
            Button {
                Task { await model.refresh(reloadCatalog: true) }
            } label: {
                Label(L("Refresh"), systemImage: "arrow.clockwise")
            }
            .help(L("Reload entries, projects and activities (⌘R)"))
            .disabled(model.isRefreshing)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                TimerBarView()
                if let problem = model.problem {
                    ProblemBanner(problem: problem)
                }
                if let notice = model.notice {
                    NoticeBanner(text: notice) { model.notice = nil }
                }
                SummaryStrip()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider()
            entryList
        }
    }

    private var sections: [DaySection] {
        TimesheetGrouping.sections(model.entries)
    }

    private var entryList: some View {
        let sections = sections
        return List(selection: $selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.entries) { entry in
                        EntryRowView(entry: entry) { model.pendingDelete = entry }
                    }
                } header: {
                    // The oldest loaded day may continue on the next page; a partial total
                    // would be wrong, so it is hidden until that day is loaded completely.
                    DayHeaderView(
                        section: section,
                        isComplete: !(model.hasMoreEntries && section.id == sections.last?.id),
                        running: model.searchTerm == nil
                            ? model.activeEntries.filter { Calendar.current.isDate($0.begin, inSameDayAs: section.day) }
                            : [])
                }
            }
            if model.hasMoreEntries {
                HStack {
                    Spacer()
                    if model.isLoadingMore {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(L("Load Earlier Entries")) {
                            Task { await model.loadMore() }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .selectionDisabled()
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: Timesheet.ID.self) { ids in
            if let entry = entry(in: ids) {
                EntryActions(entry: entry) { model.pendingDelete = entry }
            }
        } primaryAction: { ids in
            if let entry = entry(in: ids) { model.edit(entry) }
        }
        .onDeleteCommand {
            if let entry = entry(in: selection) { model.pendingDelete = entry }
        }
        .overlay {
            if sections.isEmpty { emptyState }
        }
    }

    private func entry(in ids: Set<Timesheet.ID>) -> Timesheet? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return model.entries.first { $0.id == id }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.phase == .loading || (model.isRefreshing && model.lastSync == nil) {
            ProgressView(L("Loading entries…"))
        } else if model.searchTerm != nil {
            ContentUnavailableView {
                Label(L("No Matching Entries"), systemImage: "magnifyingglass")
            } description: {
                Text(L("No entry matches “%@”.", model.searchText))
            } actions: {
                Button(L("Clear Search")) { model.searchText = "" }
            }
        } else if model.problem == nil {
            ContentUnavailableView {
                Label(L("No Entries Yet"), systemImage: "clock")
            } description: {
                Text(L("Start a timer above or add a finished entry."))
            } actions: {
                Button(L("Add Entry…")) { model.newEntry() }
            }
        }
    }
}

/// Today's and this week's totals plus the sync state.
struct SummaryStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 16) {
                total(L("Today"), seconds: model.todaySeconds(at: context.date))
                total(L("This Week"), seconds: model.weekSeconds(at: context.date))
                Spacer()
                syncStatus
            }
            .font(.callout)
        }
    }

    private func total(_ title: String, seconds: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(DurationFormat.clock(seconds))
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Format.spokenDuration(seconds))
    }

    @ViewBuilder
    private var syncStatus: some View {
        if model.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(L("Syncing…"))
            }
            .foregroundStyle(.secondary)
        } else if let lastSync = model.lastSync {
            Text(L("Synced %@", Format.time(lastSync)))
                .foregroundStyle(.secondary)
                .help(model.serverVersion.map { L("Kimai %@", $0) } ?? "")
        }
    }
}
