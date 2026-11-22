import Foundation

/// A Kimai customer (top level of the customer > project > activity hierarchy).
public struct Customer: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public var name: String
    public var number: String?
    public var color: String?
    public var visible: Bool

    public init(id: Int, name: String, number: String? = nil, color: String? = nil, visible: Bool = true) {
        self.id = id
        self.name = name
        self.number = number
        self.color = color
        self.visible = visible
    }

    enum CodingKeys: String, CodingKey {
        case id, name, number, color, visible
        case colorSafe = "color-safe"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        number = try c.decodeIfPresent(String.self, forKey: .number)
        color = try c.decodeIfPresent(String.self, forKey: .color)
            ?? c.decodeIfPresent(String.self, forKey: .colorSafe)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(number, forKey: .number)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encode(visible, forKey: .visible)
    }
}

public struct Project: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public var name: String
    public var customerID: Int?
    /// Customer name as delivered by Kimai (`parentTitle`).
    public var customerName: String?
    public var color: String?
    public var visible: Bool
    /// Whether activities without a project ("global" activities) may be booked on this project.
    public var globalActivities: Bool

    public init(
        id: Int, name: String, customerID: Int? = nil, customerName: String? = nil,
        color: String? = nil, visible: Bool = true, globalActivities: Bool = true
    ) {
        self.id = id
        self.name = name
        self.customerID = customerID
        self.customerName = customerName
        self.color = color
        self.visible = visible
        self.globalActivities = globalActivities
    }

    enum CodingKeys: String, CodingKey {
        case id, name, customer, parentTitle, color, visible, globalActivities
        case colorSafe = "color-safe"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        customerID = try c.decodeIfPresent(EntityReference.self, forKey: .customer)?.id
        customerName = try c.decodeIfPresent(String.self, forKey: .parentTitle)
        color = try c.decodeIfPresent(String.self, forKey: .color)
            ?? c.decodeIfPresent(String.self, forKey: .colorSafe)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        globalActivities = try c.decodeIfPresent(Bool.self, forKey: .globalActivities) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(customerID, forKey: .customer)
        try c.encodeIfPresent(customerName, forKey: .parentTitle)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encode(visible, forKey: .visible)
        try c.encode(globalActivities, forKey: .globalActivities)
    }
}

public struct Activity: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public var name: String
    /// `nil` for global activities that can be used with any project allowing them.
    public var projectID: Int?
    public var color: String?
    public var visible: Bool

    public init(id: Int, name: String, projectID: Int? = nil, color: String? = nil, visible: Bool = true) {
        self.id = id
        self.name = name
        self.projectID = projectID
        self.color = color
        self.visible = visible
    }

    enum CodingKeys: String, CodingKey {
        case id, name, project, color, visible
        case colorSafe = "color-safe"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        projectID = try c.decodeIfPresent(EntityReference.self, forKey: .project)?.id
        color = try c.decodeIfPresent(String.self, forKey: .color)
            ?? c.decodeIfPresent(String.self, forKey: .colorSafe)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(projectID, forKey: .project)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encode(visible, forKey: .visible)
    }
}

/// Kimai delivers related entities either as a plain id (collection endpoints)
/// or as a nested object (detail, `active` and `recent` endpoints). This accepts both.
struct EntityReference: Decodable {
    let id: Int

    private enum CodingKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let value = try? single.decode(Int.self) {
            id = value
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
    }
}

/// One time record. `end == nil` means the timer is still running.
public struct Timesheet: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public var begin: Date
    public var end: Date?
    /// Duration in seconds as calculated by Kimai (0 while running).
    public var duration: Int
    public var projectID: Int?
    public var activityID: Int?
    public var description: String?
    public var tags: [String]
    public var billable: Bool
    public var exported: Bool

    public init(
        id: Int, begin: Date, end: Date? = nil, duration: Int = 0,
        projectID: Int? = nil, activityID: Int? = nil, description: String? = nil,
        tags: [String] = [], billable: Bool = true, exported: Bool = false
    ) {
        self.id = id
        self.begin = begin
        self.end = end
        self.duration = duration
        self.projectID = projectID
        self.activityID = activityID
        self.description = description
        self.tags = tags
        self.billable = billable
        self.exported = exported
    }

    public var isRunning: Bool { end == nil }

    /// Seconds between begin and `now` for running entries, otherwise the booked duration.
    public func elapsed(at now: Date = Date()) -> Int {
        if let end {
            return duration > 0 ? duration : max(0, Int(end.timeIntervalSince(begin)))
        }
        return max(0, Int(now.timeIntervalSince(begin)))
    }

    public var trimmedDescription: String {
        (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum CodingKeys: String, CodingKey {
        case id, begin, end, duration, project, activity, description, tags, billable, exported
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        let beginString = try c.decode(String.self, forKey: .begin)
        guard let beginDate = KimaiDate.parse(beginString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .begin, in: c, debugDescription: "Unsupported date format: \(beginString)")
        }
        begin = beginDate
        if let endString = try c.decodeIfPresent(String.self, forKey: .end) {
            guard let endDate = KimaiDate.parse(endString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .end, in: c, debugDescription: "Unsupported date format: \(endString)")
            }
            end = endDate
        } else {
            end = nil
        }
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        projectID = try c.decodeIfPresent(EntityReference.self, forKey: .project)?.id
        activityID = try c.decodeIfPresent(EntityReference.self, forKey: .activity)?.id
        description = try c.decodeIfPresent(String.self, forKey: .description)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        billable = try c.decodeIfPresent(Bool.self, forKey: .billable) ?? true
        exported = try c.decodeIfPresent(Bool.self, forKey: .exported) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(KimaiDate.format(begin, timeZone: .gmt, includeOffset: true), forKey: .begin)
        try c.encodeIfPresent(end.map { KimaiDate.format($0, timeZone: .gmt, includeOffset: true) }, forKey: .end)
        try c.encode(duration, forKey: .duration)
        try c.encodeIfPresent(projectID, forKey: .project)
        try c.encodeIfPresent(activityID, forKey: .activity)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(tags, forKey: .tags)
        try c.encode(billable, forKey: .billable)
        try c.encode(exported, forKey: .exported)
    }
}

public struct ServerVersion: Decodable, Hashable, Sendable {
    public let version: String
    public let versionId: Int?

    public init(version: String, versionId: Int? = nil) {
        self.version = version
        self.versionId = versionId
    }
}

public struct KimaiUser: Decodable, Hashable, Sendable {
    public let id: Int
    public let username: String
    public let alias: String?
    public let timezone: String?
    public let language: String?

    public init(id: Int, username: String, alias: String? = nil, timezone: String? = nil, language: String? = nil) {
        self.id = id
        self.username = username
        self.alias = alias
        self.timezone = timezone
        self.language = language
    }

    public var displayName: String {
        if let alias, !alias.isEmpty { return alias }
        return username
    }

    /// Time zone of the Kimai profile. Kimai interprets submitted times in this zone.
    public var timeZone: TimeZone? {
        timezone.flatMap(TimeZone.init(identifier:))
    }
}

/// Server side tracking rules (`/api/config/timesheet`).
public struct TimesheetConfig: Decodable, Hashable, Sendable {
    public var trackingMode: String
    public var activeEntriesHardLimit: Int
    public var isAllowFutureTimes: Bool
    public var isAllowOverlapping: Bool

    public init(
        trackingMode: String = "default", activeEntriesHardLimit: Int = 1,
        isAllowFutureTimes: Bool = true, isAllowOverlapping: Bool = true
    ) {
        self.trackingMode = trackingMode
        self.activeEntriesHardLimit = activeEntriesHardLimit
        self.isAllowFutureTimes = isAllowFutureTimes
        self.isAllowOverlapping = isAllowOverlapping
    }

    enum CodingKeys: String, CodingKey {
        case trackingMode, activeEntriesHardLimit, isAllowFutureTimes, isAllowOverlapping
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackingMode = try c.decodeIfPresent(String.self, forKey: .trackingMode) ?? "default"
        activeEntriesHardLimit = try c.decodeIfPresent(Int.self, forKey: .activeEntriesHardLimit) ?? 1
        isAllowFutureTimes = try c.decodeIfPresent(Bool.self, forKey: .isAllowFutureTimes) ?? true
        isAllowOverlapping = try c.decodeIfPresent(Bool.self, forKey: .isAllowOverlapping) ?? true
    }

    /// In "punch" mode Kimai rejects manually chosen begin/end times.
    public var allowsEditingTimes: Bool { trackingMode != "punch" }
}

/// Values the user can set when creating or editing a time record.
public struct TimesheetDraft: Hashable, Sendable {
    public var begin: Date
    public var end: Date?
    public var projectID: Int?
    public var activityID: Int?
    public var description: String
    public var tags: [String]
    public var billable: Bool?

    public init(
        begin: Date = Date(), end: Date? = nil, projectID: Int? = nil, activityID: Int? = nil,
        description: String = "", tags: [String] = [], billable: Bool? = nil
    ) {
        self.begin = begin
        self.end = end
        self.projectID = projectID
        self.activityID = activityID
        self.description = description
        self.tags = tags
        self.billable = billable
    }

    public init(timesheet: Timesheet) {
        self.init(
            begin: timesheet.begin, end: timesheet.end, projectID: timesheet.projectID,
            activityID: timesheet.activityID, description: timesheet.description ?? "",
            tags: timesheet.tags, billable: timesheet.billable)
    }

    public var isComplete: Bool { projectID != nil && activityID != nil }
}

/// The fields of an existing record that should change. Everything left `nil` is not sent,
/// so Kimai keeps the stored value — including seconds the UI never showed.
public struct TimesheetChanges: Hashable, Sendable {
    public var begin: Date?
    public var end: Date?
    /// Project and activity only make sense together.
    public var booking: Booking?
    public var description: String?
    public var tags: [String]?
    public var billable: Bool?

    public init(
        begin: Date? = nil, end: Date? = nil, booking: Booking? = nil, description: String? = nil,
        tags: [String]? = nil, billable: Bool? = nil
    ) {
        self.begin = begin
        self.end = end
        self.booking = booking
        self.description = description
        self.tags = tags
        self.billable = billable
    }

    public var isEmpty: Bool { self == TimesheetChanges() }
}
