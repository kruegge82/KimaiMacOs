import KimaiKit
import SwiftUI

/// Button that shows the chosen project and activity and opens the searchable picker.
struct BookingPickerButton: View {
    @Environment(AppModel.self) private var model
    @Binding var booking: Booking?
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            BookingLabel(option: model.catalog.option(for: booking))
        }
        .buttonStyle(.bordered)
        .help(L("Choose project and activity"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            BookingPickerList(booking: $booking) { isPresented = false }
                .frame(width: 440, height: 380)
        }
    }
}

struct BookingLabel: View {
    @Environment(AppModel.self) private var model
    let option: BookingOption?

    var body: some View {
        HStack(spacing: 6) {
            if let option {
                Circle()
                    .fill(model.catalog.color(forProjectID: option.project.id))
                    .frame(width: 8, height: 8)
                // Two lines keep both names readable in narrow places.
                VStack(alignment: .leading, spacing: 0) {
                    Text(option.project.name)
                        .lineLimit(1)
                    Text(option.activity.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(L("Choose project…"))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(option?.breadcrumb ?? L("Choose project and activity"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Project and activity"))
        .accessibilityValue(option?.breadcrumb ?? L("None chosen"))
    }
}

/// Search field plus result list. Searches customer, project and activity names together;
/// without a query it offers recent choices and project-first browsing.
struct BookingPickerList: View {
    @Environment(AppModel.self) private var model
    @Binding var booking: Booking?
    var onCommit: () -> Void

    @State private var query = ""
    @State private var scope: Project?
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private enum Row: Identifiable, Hashable {
        case booking(BookingOption)
        case project(Project)
        case activity(Activity)

        var id: String {
            switch self {
            case .booking(let option): "b-\(option.project.id)-\(option.activity.id)"
            case .project(let project): "p-\(project.id)"
            case .activity(let activity): "a-\(activity.id)"
            }
        }
    }

    private struct RowSection: Identifiable {
        let id: String
        let title: String?
        let rows: [Row]
    }

    private func makeSections() -> [RowSection] {
        let catalog = model.catalog
        if let scope {
            let tokens = Catalog.tokens(query)
            let activities = catalog.activities(forProjectID: scope.id).filter { activity in
                let name = Catalog.fold(activity.name)
                return tokens.allSatisfy(name.contains)
            }
            return [RowSection(id: "activities", title: L("Activities"), rows: activities.map(Row.activity))]
        }

        let recent = model.preferences.recentBookings
        if Catalog.tokens(query).isEmpty {
            var sections: [RowSection] = []
            let recentOptions = catalog.searchBookings("", recent: recent)
            if !recentOptions.isEmpty {
                sections.append(RowSection(id: "recent", title: L("Recently Used"), rows: recentOptions.map(Row.booking)))
            }
            sections += catalog.projectGroups.map { group in
                RowSection(
                    id: "c-\(group.id)",
                    title: group.customerName.isEmpty ? L("No Customer") : group.customerName,
                    rows: group.projects.map(Row.project))
            }
            return sections
        }

        var sections: [RowSection] = []
        let matches = catalog.searchBookings(query, recent: recent, limit: 60)
        if !matches.isEmpty {
            sections.append(RowSection(id: "matches", title: nil, rows: matches.map(Row.booking)))
        }
        let projects = catalog.searchProjects(query).flatMap(\.projects).prefix(12)
        if !projects.isEmpty {
            sections.append(RowSection(id: "projects", title: L("Projects"), rows: projects.map(Row.project)))
        }
        return sections
    }

    var body: some View {
        let sections = makeSections()
        let rows = sections.flatMap(\.rows)

        VStack(spacing: 0) {
            searchField(rows: rows)
            Divider()
            if let scope {
                scopeHeader(scope)
                Divider()
            }
            if model.catalog.isEmpty {
                emptyCatalog
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                resultList(sections: sections, rows: rows)
            }
        }
        .onAppear { searchFocused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private func searchField(rows: [Row]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                scope == nil ? L("Search customer, project or activity") : L("Search activity"),
                text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { commitHighlighted(rows: rows) }
                .onKeyPress(.downArrow) {
                    highlighted = min(highlighted + 1, max(rows.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard query.isEmpty, scope != nil else { return .ignored }
                    leaveScope()
                    return .handled
                }
        }
        .padding(10)
    }

    private func scopeHeader(_ project: Project) -> some View {
        Button {
            leaveScope()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                Circle()
                    .fill(model.catalog.color(forProjectID: project.id))
                    .frame(width: 8, height: 8)
                Text([model.catalog.customerName(forProjectID: project.id), project.name]
                    .compactMap { $0 }.joined(separator: " › "))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(L("Back to all projects"))
    }

    private var emptyCatalog: some View {
        ContentUnavailableView {
            Label(L("No Projects"), systemImage: "folder.badge.questionmark")
        } description: {
            Text(L("Kimai did not return any projects you can book time on."))
        } actions: {
            Button(L("Reload")) {
                Task { await model.refresh(reloadCatalog: true) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func resultList(sections: [RowSection], rows: [Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.rows) { row in
                            let index = rows.firstIndex(of: row) ?? 0
                            Button {
                                commit(row)
                            } label: {
                                rowView(row, isHighlighted: index == highlighted)
                            }
                            .buttonStyle(.plain)
                            .id(row.id)
                            .onHover { if $0 { highlighted = index } }
                            .accessibilityAddTraits(isCurrent(row) ? .isSelected : [])
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: highlighted) {
                guard rows.indices.contains(highlighted) else { return }
                proxy.scrollTo(rows[highlighted].id)
            }
        }
    }

    private func isCurrent(_ row: Row) -> Bool {
        if case .booking(let option) = row { return option.booking == booking }
        if case .activity(let activity) = row, let scope {
            return booking == Booking(projectID: scope.id, activityID: activity.id)
        }
        return false
    }

    /// System selection colours, so the highlight works with every accent colour and with
    /// Increase Contrast.
    private static let selectionBackground = Color(nsColor: .selectedContentBackgroundColor)
    private static let selectionText = Color(nsColor: .alternateSelectedControlTextColor)

    private func rowView(_ row: Row, isHighlighted: Bool) -> some View {
        let isCurrent = isCurrent(row)
        let secondary = isHighlighted ? AnyShapeStyle(Self.selectionText) : AnyShapeStyle(.secondary)

        return HStack(spacing: 8) {
            switch row {
            case .booking(let option):
                Circle()
                    .fill(model.catalog.color(forProjectID: option.project.id))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(option.project.name) › \(option.activity.name)")
                        .lineLimit(1)
                    if let customer = option.customerName, !customer.isEmpty {
                        Text(customer)
                            .font(.caption)
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                    }
                }
            case .project(let project):
                Circle()
                    .fill(model.catalog.color(forProjectID: project.id))
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .lineLimit(1)
            case .activity(let activity):
                Text(activity.name)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
            }
            if case .project = row {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .foregroundStyle(isHighlighted ? AnyShapeStyle(Self.selectionText) : AnyShapeStyle(.primary))
        .background(
            isHighlighted ? AnyShapeStyle(Self.selectionBackground) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func commitHighlighted(rows: [Row]) {
        guard rows.indices.contains(highlighted) else { return }
        commit(rows[highlighted])
    }

    private func commit(_ row: Row) {
        switch row {
        case .booking(let option):
            booking = option.booking
            onCommit()
        case .project(let project):
            scope = project
            query = ""
            highlighted = 0
            searchFocused = true
        case .activity(let activity):
            guard let scope else { return }
            booking = Booking(projectID: scope.id, activityID: activity.id)
            onCommit()
        }
    }

    private func leaveScope() {
        scope = nil
        query = ""
        highlighted = 0
    }
}
