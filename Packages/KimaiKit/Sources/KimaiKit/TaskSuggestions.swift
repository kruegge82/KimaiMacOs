import Foundation

/// A task the user worked on before: enough to start the same thing again.
public struct TaskTemplate: Identifiable, Hashable, Sendable {
    public let description: String
    public let projectID: Int?
    public let activityID: Int?
    public let tags: [String]
    public let lastUsed: Date
    /// Most recent record this template was derived from.
    public let timesheetID: Int

    public var id: String {
        "\(projectID ?? 0)|\(activityID ?? 0)|\(Catalog.fold(description))"
    }

    public var booking: Booking? {
        guard let projectID, let activityID else { return nil }
        return Booking(projectID: projectID, activityID: activityID)
    }

    public init(
        description: String, projectID: Int?, activityID: Int?, tags: [String] = [],
        lastUsed: Date, timesheetID: Int
    ) {
        self.description = description
        self.projectID = projectID
        self.activityID = activityID
        self.tags = tags
        self.lastUsed = lastUsed
        self.timesheetID = timesheetID
    }
}

public enum TaskSuggestions {
    /// Distinct tasks (same description and booking count once), most recently used first.
    public static func recentTasks(from entries: [Timesheet], limit: Int = 20) -> [TaskTemplate] {
        var seen = Set<String>()
        var result: [TaskTemplate] = []
        for entry in entries.sorted(by: { $0.begin > $1.begin }) {
            let template = TaskTemplate(
                description: entry.trimmedDescription, projectID: entry.projectID,
                activityID: entry.activityID, tags: entry.tags, lastUsed: entry.begin,
                timesheetID: entry.id)
            guard seen.insert(template.id).inserted else { continue }
            result.append(template)
            if result.count >= limit { break }
        }
        return result
    }

    /// Tasks whose description, customer, project or activity contain every word of the query.
    public static func matching(
        _ query: String, in tasks: [TaskTemplate], catalog: Catalog, limit: Int = 6
    ) -> [TaskTemplate] {
        let tokens = Catalog.tokens(query)
        guard !tokens.isEmpty else { return [] }
        var result: [TaskTemplate] = []
        for task in tasks where !task.description.isEmpty {
            let haystack = Catalog.fold([
                task.description,
                catalog.customerName(forProjectID: task.projectID) ?? "",
                catalog.project(id: task.projectID)?.name ?? "",
                catalog.activity(id: task.activityID)?.name ?? ""
            ].joined(separator: " "))
            guard tokens.allSatisfy(haystack.contains) else { continue }
            result.append(task)
            if result.count >= limit { break }
        }
        return result
    }
}
