import Foundation

/// Formatting and parsing of durations the way Kimai users type them.
public enum DurationFormat {
    /// Longest duration `parse` accepts. Anything beyond is a typo, and unbounded input
    /// would overflow the arithmetic.
    public static let maximumSeconds = 999 * 3600

    /// `1:05` or `1:05:09`. Hours are not capped at 24.
    public static func clock(_ seconds: Int, showSeconds: Bool = false) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if showSeconds {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        }
        return String(format: "%d:%02d", hours, minutes)
    }

    /// Parses `1:30`, `1:30:15`, `1h 30m`, `1h30`, `90m`, `45 min`, `2 Std`, `1.5`, `1,5`.
    /// A bare number means hours, as in Kimai's own duration field. Returns seconds.
    public static func parse(_ input: String) -> Int? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        if text.contains(":") {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count) else { return nil }
            var values: [Int] = []
            for part in parts {
                guard let value = Int(part.trimmingCharacters(in: .whitespaces)), value >= 0 else { return nil }
                values.append(value)
            }
            guard values[0] <= maximumSeconds / 3600, values[1] < 60, values.count == 2 || values[2] < 60 else {
                return nil
            }
            return bounded(Double(values[0] * 3600 + values[1] * 60 + (values.count == 3 ? values[2] : 0)))
        }

        if let hours = decimal(text) {
            return bounded(hours * 3600)
        }

        // Unit notation: sequences of <number><unit>, with an optional trailing bare number
        // after hours meaning minutes ("1h30").
        var total = 0.0
        var matchedAny = false
        var lastUnitWasHours = false
        var rest = Substring(text)
        while true {
            rest = rest.drop(while: { $0.isWhitespace })
            guard !rest.isEmpty else { break }
            let numberText = rest.prefix(while: { $0.isNumber || $0 == "." || $0 == "," })
            guard !numberText.isEmpty, let number = decimal(String(numberText)) else { return nil }
            rest = rest.dropFirst(numberText.count).drop(while: { $0.isWhitespace })
            let unitText = rest.prefix(while: { $0.isLetter || $0 == "." })
            rest = rest.dropFirst(unitText.count)
            let unit = unitText.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            switch unit {
            case "h", "hr", "hrs", "hour", "hours", "std", "stunde", "stunden":
                total += number * 3600
                lastUnitWasHours = true
            case "m", "min", "mins", "minute", "minutes", "minuten":
                total += number * 60
                lastUnitWasHours = false
            case "s", "sec", "secs", "sek", "second", "seconds", "sekunden":
                total += number
                lastUnitWasHours = false
            case "" where lastUnitWasHours:
                total += number * 60
                lastUnitWasHours = false
            default:
                return nil
            }
            matchedAny = true
        }
        return matchedAny ? bounded(total) : nil
    }

    private static func bounded(_ seconds: Double) -> Int? {
        guard seconds.isFinite, seconds >= 0, seconds <= Double(maximumSeconds) else { return nil }
        return Int(seconds.rounded())
    }

    private static func decimal(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              normalized.filter({ $0 == "." }).count <= 1,
              normalized != "."
        else { return nil }
        return Double(normalized)
    }
}
