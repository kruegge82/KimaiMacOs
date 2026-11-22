import Foundation

/// Date handling for the Kimai API.
///
/// Kimai returns ISO 8601 timestamps with a numeric offset (`2026-11-21T07:03:45-0700`).
/// When writing, Kimai expects "HTML5 local" timestamps without offset and interprets them
/// in the time zone of the authenticated user's profile, so the profile zone must be used
/// for formatting — not the zone of this Mac.
public enum KimaiDate {
    private static func makeFormatter(_ format: String, timeZone: TimeZone = .gmt) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    // DateFormatter is thread-safe for parsing and formatting as long as it is not mutated,
    // which never happens after creation here.
    private static let offsetParsers: [DateFormatter] = [
        makeFormatter("yyyy-MM-dd'T'HH:mm:ssZ"),
        makeFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
        makeFormatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ")
    ]

    public static func parse(_ string: String) -> Date? {
        for parser in offsetParsers {
            if let date = parser.date(from: string) { return date }
        }
        // Timestamp without offset: best effort in the zone of this Mac.
        return makeFormatter("yyyy-MM-dd'T'HH:mm:ss", timeZone: .current).date(from: string)
    }

    public static func format(_ date: Date, timeZone: TimeZone, includeOffset: Bool = false) -> String {
        let format = includeOffset ? "yyyy-MM-dd'T'HH:mm:ssZ" : "yyyy-MM-dd'T'HH:mm:ss"
        return makeFormatter(format, timeZone: timeZone).string(from: date)
    }
}
