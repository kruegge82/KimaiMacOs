#if DEBUG
import Foundation
import KimaiKit

/// Realistic sample data for SwiftUI previews and UI snapshots. Never touches the network.
enum PreviewData {
    static let catalog = Catalog(
        customers: [
            Customer(id: 1, name: "Nordwind Logistik", color: "#2E86DE"),
            Customer(id: 2, name: "Atelier Lindgrün", color: "#27AE60"),
            Customer(id: 3, name: "Intern", color: "#8E44AD")
        ],
        projects: [
            Project(id: 10, name: "Lagerverwaltung 2.0", customerID: 1, color: "#2E86DE"),
            Project(id: 11, name: "Schnittstelle Versanddienstleister", customerID: 1, color: "#54A0FF"),
            Project(id: 20, name: "Webshop Relaunch", customerID: 2, color: "#27AE60"),
            Project(id: 30, name: "Organisation", customerID: 3, color: "#8E44AD")
        ],
        activities: [
            Activity(id: 100, name: "Entwicklung"),
            Activity(id: 101, name: "Besprechung"),
            Activity(id: 102, name: "Code-Review"),
            Activity(id: 103, name: "Support"),
            Activity(id: 120, name: "Design", projectID: 20),
            Activity(id: 130, name: "Buchhaltung", projectID: 30)
        ],
        fetchedAt: Date())

    private static func at(daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date()))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private static func entry(
        _ id: Int, daysAgo: Int, from: (Int, Int), minutes: Int, _ description: String?,
        project: Int, activity: Int, tags: [String] = [], exported: Bool = false
    ) -> Timesheet {
        let begin = at(daysAgo: daysAgo, from.0, from.1)
        return Timesheet(
            id: id, begin: begin, end: begin.addingTimeInterval(Double(minutes) * 60), duration: minutes * 60,
            projectID: project, activityID: activity, description: description, tags: tags, exported: exported)
    }

    static let entries: [Timesheet] = [
        entry(9, daysAgo: 0, from: (8, 5), minutes: 85, "Etikettendruck: Fehler bei Umlauten beheben", project: 10, activity: 100, tags: ["bug"]),
        entry(8, daysAgo: 0, from: (9, 30), minutes: 30, "Daily", project: 10, activity: 101),
        entry(7, daysAgo: 0, from: (10, 0), minutes: 110, "Tracking-Webhook für DHL anbinden", project: 11, activity: 100),
        entry(6, daysAgo: 1, from: (8, 15), minutes: 140, "Produktseite: neue Bildergalerie", project: 20, activity: 120),
        entry(5, daysAgo: 1, from: (10, 45), minutes: 45, "Pull Request Bestandsabgleich", project: 10, activity: 102),
        entry(4, daysAgo: 1, from: (13, 0), minutes: 200, "Tracking-Webhook für DHL anbinden", project: 11, activity: 100),
        entry(3, daysAgo: 2, from: (9, 0), minutes: 60, nil, project: 30, activity: 130, exported: true),
        entry(2, daysAgo: 2, from: (10, 15), minutes: 95, "Rückfrage Retourenlabel", project: 11, activity: 103, tags: ["kunde"]),
        entry(1, daysAgo: 2, from: (13, 30), minutes: 180, "Checkout: Zahlungsarten neu anordnen", project: 20, activity: 100)
    ]

    static var running: Timesheet {
        Timesheet(
            id: 10, begin: Date().addingTimeInterval(-47 * 60 - 12), projectID: 20, activityID: 100,
            description: "Checkout: Zahlungsarten neu anordnen")
    }

    /// A fully populated model that is not connected to any server.
    static func model(running isRunning: Bool, problem: KimaiError? = nil) -> AppModel {
        let defaults = UserDefaults(suiteName: "app.kimaitimer.mac.preview") ?? .standard
        defaults.removePersistentDomain(forName: "app.kimaitimer.mac.preview")
        let preferences = Preferences(defaults: defaults)
        preferences.serverURL = "https://kimai.example.com"
        preferences.recentBookings = [
            Booking(projectID: 20, activityID: 100), Booking(projectID: 11, activityID: 100),
            Booking(projectID: 10, activityID: 101)
        ]
        let model = AppModel(
            preferences: preferences, secrets: MemorySecretStore(),
            cache: CatalogCache(fileName: "preview-catalog.json"))
        model.phase = .ready
        model.catalog = catalog
        model.entries = entries
        model.weekEntries = entries
        model.recentTasks = TaskSuggestions.recentTasks(from: entries, limit: 12)
        model.activeEntries = isRunning ? [running] : []
        model.draftBooking = Booking(projectID: 20, activityID: 100)
        model.serverVersion = "2.60.0"
        model.user = KimaiUser(id: 1, username: "anna", alias: "Anna Beispiel", timezone: TimeZone.current.identifier)
        model.lastSync = Date()
        model.hasMoreEntries = true
        if let problem { model.syncProblem = Problem(error: problem) }
        model.updateMenuBarText()
        return model
    }
}
#endif
