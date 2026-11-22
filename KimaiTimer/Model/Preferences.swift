import Foundation
import KimaiKit
import Observation

enum AuthMode: String, CaseIterable, Identifiable {
    case bearer
    case legacy
    var id: String { rawValue }
}

/// A global keyboard shortcut as stored in the preferences.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value, reduced to ⌃⌥⇧⌘.
    var modifiers: UInt
    var display: String
}

/// Settings that are not secret. The API token lives in the Keychain.
@Observable
final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    var serverURL: String { didSet { defaults.set(serverURL, forKey: Key.serverURL) } }
    var authMode: AuthMode { didSet { defaults.set(authMode.rawValue, forKey: Key.authMode) } }
    var username: String { didSet { defaults.set(username, forKey: Key.username) } }
    var showSecondsInMenuBar: Bool { didSet { defaults.set(showSecondsInMenuBar, forKey: Key.showSeconds) } }
    var idleDetectionEnabled: Bool { didSet { defaults.set(idleDetectionEnabled, forKey: Key.idleEnabled) } }
    var idleMinutes: Int { didSet { defaults.set(idleMinutes, forKey: Key.idleMinutes) } }
    var lastBooking: Booking? { didSet { store(lastBooking, forKey: Key.lastBooking) } }
    var recentBookings: [Booking] { didSet { store(recentBookings, forKey: Key.recentBookings) } }
    var shortcut: Shortcut? { didSet { store(shortcut, forKey: Key.shortcut) } }

    private enum Key {
        static let serverURL = "serverURL"
        static let authMode = "authMode"
        static let username = "username"
        static let showSeconds = "showSecondsInMenuBar"
        static let idleEnabled = "idleDetectionEnabled"
        static let idleMinutes = "idleMinutes"
        static let lastBooking = "lastBooking"
        static let recentBookings = "recentBookings"
        static let shortcut = "globalShortcut"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.idleEnabled: true, Key.idleMinutes: 10])
        serverURL = defaults.string(forKey: Key.serverURL) ?? ""
        authMode = AuthMode(rawValue: defaults.string(forKey: Key.authMode) ?? "") ?? .bearer
        username = defaults.string(forKey: Key.username) ?? ""
        showSecondsInMenuBar = defaults.bool(forKey: Key.showSeconds)
        idleDetectionEnabled = defaults.bool(forKey: Key.idleEnabled)
        idleMinutes = max(1, defaults.integer(forKey: Key.idleMinutes))
        lastBooking = Self.load(Booking.self, from: defaults, forKey: Key.lastBooking)
        recentBookings = Self.load([Booking].self, from: defaults, forKey: Key.recentBookings) ?? []
        shortcut = Self.load(Shortcut.self, from: defaults, forKey: Key.shortcut)
    }

    /// Remembers a booking as the default for the next timer and as a recent choice.
    func remember(_ booking: Booking) {
        lastBooking = booking
        var recent = recentBookings.filter { $0 != booking }
        recent.insert(booking, at: 0)
        recentBookings = Array(recent.prefix(8))
    }

    private func store<Value: Encodable>(_ value: Value?, forKey key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, forKey key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
