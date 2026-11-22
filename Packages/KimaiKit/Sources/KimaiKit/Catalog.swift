import Foundation

/// A project/activity pair — what a time record is booked on.
public struct Booking: Hashable, Codable, Sendable {
    public var projectID: Int
    public var activityID: Int

    public init(projectID: Int, activityID: Int) {
        self.projectID = projectID
        self.activityID = activityID
    }
}

/// A booking resolved against the catalog, ready for display.
public struct BookingOption: Identifiable, Hashable, Sendable {
    public let project: Project
    public let activity: Activity
    public let customerName: String?

    public var booking: Booking { Booking(projectID: project.id, activityID: activity.id) }
    public var id: Booking { booking }

    /// "Customer › Project › Activity"
    public var breadcrumb: String {
        [customerName, project.name, activity.name]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " › ")
    }
}

public struct ProjectGroup: Identifiable, Hashable, Sendable {
    public let customerID: Int?
    public let customerName: String
    public let projects: [Project]
    public var id: Int { customerID ?? -1 }
}

/// Customers, projects and activities of a Kimai installation with the lookups the UI needs.
public struct Catalog: Sendable {
    public let customers: [Customer]
    public let projects: [Project]
    public let activities: [Activity]
    public let fetchedAt: Date

    private let customersByID: [Int: Customer]
    private let projectsByID: [Int: Project]
    private let activitiesByID: [Int: Activity]
    private let activitiesByProject: [Int: [Activity]]
    private let globalActivities: [Activity]
    private let foldedProjectText: [Int: String]
    private let foldedActivityText: [Int: String]
    /// Visible projects grouped by customer, both sorted by name.
    public let projectGroups: [ProjectGroup]

    public static let empty = Catalog(customers: [], projects: [], activities: [], fetchedAt: .distantPast)

    public init(customers: [Customer], projects: [Project], activities: [Activity], fetchedAt: Date) {
        let byName: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        let sortedCustomers = customers.sorted { byName($0.name, $1.name) }
        let sortedProjects = projects.sorted { byName($0.name, $1.name) }
        let sortedActivities = activities.sorted { byName($0.name, $1.name) }
        let customerLookup = Dictionary(sortedCustomers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var projectText: [Int: String] = [:]
        for project in sortedProjects {
            let customer = project.customerID.flatMap { customerLookup[$0]?.name } ?? project.customerName ?? ""
            projectText[project.id] = Self.fold(customer + " " + project.name)
        }

        let visibleActivities = sortedActivities.filter(\.visible)
        var byProject: [Int: [Activity]] = [:]
        var globals: [Activity] = []
        for activity in visibleActivities {
            if let projectID = activity.projectID {
                byProject[projectID, default: []].append(activity)
            } else {
                globals.append(activity)
            }
        }

        let groups = Dictionary(grouping: sortedProjects.filter(\.visible), by: { $0.customerID })
            .map { customerID, projects in
                let name = customerID.flatMap { customerLookup[$0]?.name } ?? projects.first?.customerName ?? ""
                return ProjectGroup(customerID: customerID, customerName: name, projects: projects)
            }
            .sorted { byName($0.customerName, $1.customerName) }

        self.customers = sortedCustomers
        self.projects = sortedProjects
        self.activities = sortedActivities
        self.fetchedAt = fetchedAt
        customersByID = customerLookup
        projectsByID = Dictionary(sortedProjects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        activitiesByID = Dictionary(sortedActivities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        activitiesByProject = byProject
        globalActivities = globals
        foldedProjectText = projectText
        foldedActivityText = Dictionary(
            sortedActivities.map { ($0.id, Self.fold($0.name)) }, uniquingKeysWith: { first, _ in first })
        projectGroups = groups
    }

    public var isEmpty: Bool { projects.isEmpty && activities.isEmpty }

    public func isStale(at now: Date = Date(), maxAge: TimeInterval = 3600) -> Bool {
        now.timeIntervalSince(fetchedAt) > maxAge
    }

    public func customer(id: Int?) -> Customer? { id.flatMap { customersByID[$0] } }
    public func project(id: Int?) -> Project? { id.flatMap { projectsByID[$0] } }
    public func activity(id: Int?) -> Activity? { id.flatMap { activitiesByID[$0] } }

    public func customerName(forProjectID id: Int?) -> String? {
        guard let project = project(id: id) else { return nil }
        return customer(id: project.customerID)?.name ?? project.customerName
    }

    /// Activities that may be booked on a project: its own first, then global ones if allowed.
    public func activities(forProjectID id: Int) -> [Activity] {
        guard let project = projectsByID[id] else { return [] }
        let own = activitiesByProject[id] ?? []
        return project.globalActivities ? own + globalActivities : own
    }

    public func isValid(_ booking: Booking) -> Bool {
        guard let project = projectsByID[booking.projectID], project.visible,
              let activity = activitiesByID[booking.activityID], activity.visible
        else { return false }
        if let owner = activity.projectID { return owner == project.id }
        return project.globalActivities
    }

    public func option(for booking: Booking?) -> BookingOption? {
        guard let booking, let project = projectsByID[booking.projectID],
              let activity = activitiesByID[booking.activityID]
        else { return nil }
        return BookingOption(
            project: project, activity: activity, customerName: customerName(forProjectID: project.id))
    }

    /// Searches customer, project and activity names together. Every word of the query has to
    /// appear somewhere in the breadcrumb. Recently used bookings are listed first.
    public func searchBookings(_ query: String, recent: [Booking] = [], limit: Int = 60) -> [BookingOption] {
        let tokens = Self.tokens(query)
        var results: [BookingOption] = []
        var seen = Set<Booking>()

        func matches(_ booking: Booking) -> Bool {
            guard !tokens.isEmpty else { return true }
            let projectText = foldedProjectText[booking.projectID] ?? ""
            let activityText = foldedActivityText[booking.activityID] ?? ""
            return tokens.allSatisfy { projectText.contains($0) || activityText.contains($0) }
        }

        for booking in recent where isValid(booking) && matches(booking) && !seen.contains(booking) {
            if let option = option(for: booking) {
                results.append(option)
                seen.insert(booking)
            }
        }
        guard !tokens.isEmpty else { return results }

        for group in projectGroups {
            for project in group.projects {
                let projectText = foldedProjectText[project.id] ?? ""
                let remaining = tokens.filter { !projectText.contains($0) }
                for activity in activities(forProjectID: project.id) {
                    if !remaining.isEmpty {
                        let activityText = foldedActivityText[activity.id] ?? ""
                        guard remaining.allSatisfy(activityText.contains) else { continue }
                    }
                    let booking = Booking(projectID: project.id, activityID: activity.id)
                    guard seen.insert(booking).inserted else { continue }
                    results.append(BookingOption(
                        project: project, activity: activity,
                        customerName: group.customerName.isEmpty ? nil : group.customerName))
                    if results.count >= limit { return results }
                }
            }
        }
        return results
    }

    /// Visible projects whose customer or project name contains every word of the query.
    public func searchProjects(_ query: String) -> [ProjectGroup] {
        let tokens = Self.tokens(query)
        guard !tokens.isEmpty else { return projectGroups }
        return projectGroups.compactMap { group in
            let projects = group.projects.filter { project in
                let text = foldedProjectText[project.id] ?? ""
                return tokens.allSatisfy(text.contains)
            }
            return projects.isEmpty
                ? nil
                : ProjectGroup(customerID: group.customerID, customerName: group.customerName, projects: projects)
        }
    }

    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    public static func tokens(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace || $0 == "›" || $0 == ">" || $0 == "/" })
            .map(String.init)
    }
}

extension Catalog: Equatable {
    public static func == (lhs: Catalog, rhs: Catalog) -> Bool {
        lhs.fetchedAt == rhs.fetchedAt && lhs.customers == rhs.customers
            && lhs.projects == rhs.projects && lhs.activities == rhs.activities
    }
}

extension Catalog: Codable {
    private enum CodingKeys: String, CodingKey { case customers, projects, activities, fetchedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            customers: c.decode([Customer].self, forKey: .customers),
            projects: c.decode([Project].self, forKey: .projects),
            activities: c.decode([Activity].self, forKey: .activities),
            fetchedAt: c.decode(Date.self, forKey: .fetchedAt))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(customers, forKey: .customers)
        try c.encode(projects, forKey: .projects)
        try c.encode(activities, forKey: .activities)
        try c.encode(fetchedAt, forKey: .fetchedAt)
    }
}
