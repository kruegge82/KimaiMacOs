import KimaiKit
import SwiftUI

enum Format {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "09:00 – 10:30", with the end date added when the record crosses midnight.
    static func timeRange(begin: Date, end: Date?, calendar: Calendar = .current) -> String {
        guard let end else { return L("since %@", time(begin)) }
        if calendar.isDate(begin, inSameDayAs: end) {
            return "\(time(begin)) – \(time(end))"
        }
        let endDay = end.formatted(.dateTime.day().month(.abbreviated))
        return "\(time(begin)) – \(time(end)) (\(endDay))"
    }

    static func dayTitle(_ day: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide)
        if !calendar.isDate(day, equalTo: now, toGranularity: .year) {
            style = style.year()
        }
        let formatted = day.formatted(style)
        if calendar.isDateInToday(day) { return L("Today") + " · " + formatted }
        if calendar.isDateInYesterday(day) { return L("Yesterday") + " · " + formatted }
        return formatted
    }

    /// Spoken form for VoiceOver: "1 hour, 5 minutes".
    static func spokenDuration(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds) / 60 * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}

extension Color {
    /// Parses Kimai colour strings such as `#2ECC40`. Returns `nil` for anything else.
    init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

extension Catalog {
    /// Colour of the project, falling back to its customer and finally to grey.
    func color(forProjectID id: Int?) -> Color {
        let project = project(id: id)
        return Color(hex: project?.color)
            ?? Color(hex: customer(id: project?.customerID)?.color)
            ?? .secondary
    }

    /// "Customer › Project › Activity" for whatever parts are known.
    func breadcrumb(projectID: Int?, activityID: Int?) -> String {
        let parts = [
            customerName(forProjectID: projectID),
            project(id: projectID)?.name,
            activity(id: activityID)?.name
        ]
        let known = parts.compactMap { $0?.isEmpty == false ? $0 : nil }
        return known.isEmpty ? L("No project") : known.joined(separator: " › ")
    }
}
