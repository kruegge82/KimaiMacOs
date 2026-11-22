import Foundation

/// Looks up a user-facing string in `Localizable.xcstrings`. The English text is the key.
/// `scripts/check-l10n.py` verifies that every key used with `L(…)` has a German translation.
nonisolated func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: .current, arguments: arguments)
}
