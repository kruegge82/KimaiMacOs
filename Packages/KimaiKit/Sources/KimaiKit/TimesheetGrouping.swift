import Foundation

/// All records that began on one calendar day.
public struct DaySection: Identifiable, Hashable, Sendable {
    /// Start of the day in the calendar used for grouping.
    public let day: Date
    public var entries: [Timesheet]
    public var id: Date { day }

    public init(day: Date, entries: [Timesheet]) {
        self.day = day
        self.entries = entries
    }

    public func totalSeconds(at now: Date = Date()) -> Int {
        entries.reduce(0) { $0 + $1.elapsed(at: now) }
    }
}

public enum TimesheetGrouping {
    /// Groups records by the day they began (Kimai's own convention), newest day first and
    /// newest record first within a day.
    public static func sections(_ entries: [Timesheet], calendar: Calendar = .current) -> [DaySection] {
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.begin) }
        return grouped
            .map { day, entries in
                DaySection(day: day, entries: entries.sorted { ($0.begin, $0.id) > ($1.begin, $1.id) })
            }
            .sorted { $0.day > $1.day }
    }

    /// Sum of all records that began within the interval; running records count up to `now`.
    public static func total(of entries: [Timesheet], in interval: DateInterval, at now: Date = Date()) -> Int {
        entries.reduce(0) { sum, entry in
            entry.begin >= interval.start && entry.begin < interval.end ? sum + entry.elapsed(at: now) : sum
        }
    }

    public static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86400)
    }

    public static func week(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86400)
    }
}
