import Foundation
import Testing
@testable import KimaiKit

@Suite struct DateTests {
    @Test func parsesKimaiOffsetFormats() {
        let expected = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
        #expect(KimaiDate.parse("2023-11-14T23:13:20+0100") == expected)
        #expect(KimaiDate.parse("2023-11-14T23:13:20+01:00") == expected)
        #expect(KimaiDate.parse("2023-11-14T22:13:20Z") == expected)
        #expect(KimaiDate.parse("2023-11-14T15:13:20-0700") == expected)
        #expect(KimaiDate.parse("not a date") == nil)
    }

    @Test func formatsInProfileTimeZoneWithoutOffset() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(KimaiDate.format(date, timeZone: Fixture.berlin) == "2023-11-14T23:13:20")
        #expect(KimaiDate.format(date, timeZone: TimeZone(identifier: "America/Phoenix")!) == "2023-11-14T15:13:20")
        #expect(KimaiDate.format(date, timeZone: .gmt, includeOffset: true) == "2023-11-14T22:13:20+0000")
    }
}

@Suite struct DecodingTests {
    @Test func decodesCollectionFormat() throws {
        let entries = try JSONDecoder().decode([Timesheet].self, from: Data(Fixture.timesheetCollection.utf8))
        #expect(entries.count == 2)
        let first = entries[0]
        #expect(first.id == 751)
        #expect(first.projectID == 50)
        #expect(first.activityID == 2818)
        #expect(first.duration == 47520)
        #expect(first.tags == ["urgent", "web"])
        #expect(first.isRunning == false)
        #expect(first.begin == Fixture.date("2026-12-04T16:08:00+0000"))
        #expect(entries[1].description == nil)
        #expect(entries[1].exported)
        #expect(entries[1].billable == false)
    }

    @Test func decodesExpandedFormatWithNestedEntities() throws {
        let entries = try JSONDecoder().decode([Timesheet].self, from: Data(Fixture.activeTimesheets.utf8))
        let running = try #require(entries.first)
        #expect(running.isRunning)
        #expect(running.projectID == 189)
        #expect(running.activityID == 2276)
        let now = running.begin.addingTimeInterval(125)
        #expect(running.elapsed(at: now) == 125)
    }

    @Test func timesheetSurvivesCacheRoundTrip() throws {
        let original = try JSONDecoder().decode([Timesheet].self, from: Data(Fixture.timesheetCollection.utf8))
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode([Timesheet].self, from: data) == original)
    }

    @Test func decodesMasterDataWithColorFallback() throws {
        let json = """
        [{"parentTitle":"Ward","customer":6,"color-safe":"#2ECC40","id":103,"name":"A dignissimos",
          "visible":true,"billable":true,"globalActivities":false,"color":null}]
        """
        let project = try #require(try JSONDecoder().decode([Project].self, from: Data(json.utf8)).first)
        #expect(project.customerID == 6)
        #expect(project.customerName == "Ward")
        #expect(project.color == "#2ECC40")
        #expect(project.globalActivities == false)

        let activityJSON = ##"[{"project":null,"id":1,"name":"Global","visible":true,"color":"#123456"}]"##
        let activity = try #require(try JSONDecoder().decode([Activity].self, from: Data(activityJSON.utf8)).first)
        #expect(activity.projectID == nil)
        #expect(activity.color == "#123456")
    }

    @Test func catalogSurvivesCacheRoundTrip() throws {
        let data = try JSONEncoder().encode(Fixture.catalog)
        #expect(try JSONDecoder().decode(Catalog.self, from: data) == Fixture.catalog)
    }

    @Test func userTimeZone() throws {
        let json = #"{"id":2,"username":"user","alias":"John Doe","timezone":"America/Vancouver","language":"en"}"#
        let user = try JSONDecoder().decode(KimaiUser.self, from: Data(json.utf8))
        #expect(user.displayName == "John Doe")
        #expect(user.timeZone == Fixture.vancouver)
    }
}

@Suite struct DurationTests {
    @Test(arguments: [
        ("1:30", 5400), ("0:05", 300), ("1:30:15", 5415), ("12:00", 43200),
        ("1h 30m", 5400), ("1h30", 5400), ("1h30m", 5400), ("90m", 5400), ("45 min", 2700),
        ("2 Std", 7200), ("1 Stunde 15 Minuten", 4500), ("30s", 30),
        ("1.5", 5400), ("1,5", 5400), ("2", 7200), ("0,25", 900), (" 1:00 ", 3600), ("1.5h", 5400)
    ])
    func parsesValidInput(input: String, seconds: Int) {
        #expect(DurationFormat.parse(input) == seconds)
    }

    @Test(arguments: [
        "", "abc", "1:75", "1:2:3:4", "-1", "1x", "1..5", "h", ":", "1:-5",
        // Must be rejected instead of overflowing.
        "9223372036854775807:00", "1000:00", "99999999999999999999", "1e400", "5000h", "99999999999999999999h"
    ])
    func rejectsInvalidInput(input: String) {
        #expect(DurationFormat.parse(input) == nil)
    }

    @Test func formatsClock() {
        #expect(DurationFormat.clock(0) == "0:00")
        #expect(DurationFormat.clock(3900) == "1:05")
        #expect(DurationFormat.clock(3909, showSeconds: true) == "1:05:09")
        #expect(DurationFormat.clock(100 * 3600) == "100:00")
        #expect(DurationFormat.clock(-5) == "0:00")
    }
}

@Suite struct CatalogTests {
    let catalog = Fixture.catalog

    @Test func activitiesRespectProjectRules() {
        // Project with global activities: own first, then global ones.
        #expect(catalog.activities(forProjectID: 20).map(\.id) == [120, 101, 100])
        // Project without global activities only offers its own.
        #expect(catalog.activities(forProjectID: 11).map(\.id) == [110])
        #expect(catalog.activities(forProjectID: 999).isEmpty)
    }

    @Test func validatesBookings() {
        #expect(catalog.isValid(Booking(projectID: 10, activityID: 100)))
        #expect(catalog.isValid(Booking(projectID: 11, activityID: 110)))
        #expect(!catalog.isValid(Booking(projectID: 11, activityID: 100))) // globals not allowed
        #expect(!catalog.isValid(Booking(projectID: 10, activityID: 110))) // foreign activity
        #expect(!catalog.isValid(Booking(projectID: 21, activityID: 100))) // hidden project
        #expect(!catalog.isValid(Booking(projectID: 20, activityID: 121))) // hidden activity
    }

    @Test func groupsVisibleProjectsByCustomer() {
        #expect(catalog.projectGroups.map(\.customerName) == ["Acme Corp", "Müller GmbH"])
        #expect(catalog.projectGroups[0].projects.map(\.id) == [20])
        #expect(catalog.projectGroups[1].projects.map(\.name) == ["Wartung", "Webshop Relaunch"])
    }

    @Test func searchMatchesAcrossCustomerProjectAndActivity() {
        let result = catalog.searchBookings("muller entw")
        #expect(result.map(\.booking) == [Booking(projectID: 10, activityID: 100)])
        #expect(result.first?.breadcrumb == "Müller GmbH › Webshop Relaunch › Entwicklung")

        #expect(catalog.searchBookings("server").map(\.booking) == [Booking(projectID: 11, activityID: 110)])
        #expect(catalog.searchBookings("archiv").isEmpty)
        #expect(catalog.searchBookings("zzz").isEmpty)
    }

    @Test func searchListsRecentBookingsFirstAndDropsInvalidOnes() {
        let recent = [
            Booking(projectID: 20, activityID: 120),
            Booking(projectID: 21, activityID: 100), // hidden project
            Booking(projectID: 10, activityID: 101)
        ]
        #expect(catalog.searchBookings("", recent: recent).map(\.booking) == [recent[0], recent[2]])

        let acme = catalog.searchBookings("acme", recent: recent)
        #expect(acme.first?.booking == recent[0])
        #expect(Set(acme.map(\.booking)).count == acme.count)
        #expect(acme.count == 3)
    }

    @Test func searchHonoursLimit() {
        #expect(catalog.searchBookings("e", limit: 2).count == 2)
    }

    @Test func searchProjectsFiltersGroups() {
        #expect(catalog.searchProjects("").count == 2)
        let groups = catalog.searchProjects("web")
        #expect(groups.count == 1)
        #expect(groups[0].projects.map(\.id) == [10])
    }

    @Test func staleness() {
        let now = catalog.fetchedAt.addingTimeInterval(3000)
        #expect(!catalog.isStale(at: now))
        #expect(catalog.isStale(at: now.addingTimeInterval(1000)))
        #expect(Catalog.empty.isStale())
    }
}

@Suite struct GroupingTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Fixture.berlin
        calendar.firstWeekday = 2
        return calendar
    }

    func entry(_ id: Int, _ begin: String, minutes: Int?) -> Timesheet {
        let start = Fixture.date(begin)
        return Timesheet(
            id: id, begin: start, end: minutes.map { start.addingTimeInterval(Double($0) * 60) },
            duration: (minutes ?? 0) * 60, projectID: 10, activityID: 100)
    }

    @Test func groupsByBeginDayNewestFirst() {
        let entries = [
            entry(1, "2026-11-20T09:00:00+0100", minutes: 60),
            entry(2, "2026-11-21T23:30:00+0100", minutes: 90), // crosses midnight, stays on the 21st
            entry(3, "2026-11-21T08:00:00+0100", minutes: 30)
        ]
        let sections = TimesheetGrouping.sections(entries, calendar: calendar)
        #expect(sections.count == 2)
        #expect(sections[0].entries.map(\.id) == [2, 3])
        #expect(sections[0].totalSeconds() == 120 * 60)
        #expect(sections[1].entries.map(\.id) == [1])
    }

    @Test func totalsIncludeRunningPortion() {
        let now = Fixture.date("2026-11-21T12:00:00+0100")
        let entries = [
            entry(1, "2026-11-21T08:00:00+0100", minutes: 30),
            entry(2, "2026-11-21T11:00:00+0100", minutes: nil),
            entry(3, "2026-11-16T08:00:00+0100", minutes: 120), // Monday of the same week
            entry(4, "2026-11-15T08:00:00+0100", minutes: 600)  // Sunday before
        ]
        let day = TimesheetGrouping.day(containing: now, calendar: calendar)
        let week = TimesheetGrouping.week(containing: now, calendar: calendar)
        #expect(TimesheetGrouping.total(of: entries, in: day, at: now) == 90 * 60)
        #expect(TimesheetGrouping.total(of: entries, in: week, at: now) == 210 * 60)
    }
}

@Suite struct SuggestionTests {
    func entry(_ id: Int, _ description: String?, project: Int, activity: Int, daysAgo: Double) -> Timesheet {
        let begin = Date(timeIntervalSince1970: 2_000_000_000 - daysAgo * 86400)
        return Timesheet(
            id: id, begin: begin, end: begin.addingTimeInterval(600), duration: 600,
            projectID: project, activityID: activity, description: description)
    }

    @Test func deduplicatesByDescriptionAndBooking() {
        let entries = [
            entry(1, "Deploy", project: 10, activity: 100, daysAgo: 3),
            entry(2, " deploy ", project: 10, activity: 100, daysAgo: 1),
            entry(3, "Deploy", project: 20, activity: 120, daysAgo: 2),
            entry(4, nil, project: 10, activity: 101, daysAgo: 0)
        ]
        let tasks = TaskSuggestions.recentTasks(from: entries)
        #expect(tasks.map(\.timesheetID) == [4, 2, 3])
        #expect(tasks[1].description == "deploy")
        #expect(TaskSuggestions.recentTasks(from: entries, limit: 1).count == 1)
    }

    @Test func matchesDescriptionAndBookingNames() {
        let tasks = TaskSuggestions.recentTasks(from: [
            entry(1, "Deploy Shop", project: 10, activity: 100, daysAgo: 1),
            entry(2, "Standup", project: 20, activity: 120, daysAgo: 2),
            entry(3, nil, project: 20, activity: 120, daysAgo: 0)
        ])
        let catalog = Fixture.catalog
        #expect(TaskSuggestions.matching("dep", in: tasks, catalog: catalog).map(\.timesheetID) == [1])
        #expect(TaskSuggestions.matching("acme", in: tasks, catalog: catalog).map(\.timesheetID) == [2])
        #expect(TaskSuggestions.matching("müller shop", in: tasks, catalog: catalog).map(\.timesheetID) == [1])
        #expect(TaskSuggestions.matching("", in: tasks, catalog: catalog).isEmpty)
    }
}

@Suite struct URLNormalizationTests {
    @Test(arguments: [
        ("kimai.example.com", "https://kimai.example.com"),
        ("  https://kimai.example.com/  ", "https://kimai.example.com"),
        ("https://example.com/kimai/", "https://example.com/kimai"),
        ("https://example.com/kimai/api", "https://example.com/kimai"),
        ("https://example.com/api/doc", "https://example.com"),
        ("http://localhost:8001", "http://localhost:8001"),
        ("HTTPS://Example.com?x=1#y", "https://Example.com")
    ])
    func normalizes(input: String, expected: String) {
        #expect(ConnectionConfiguration.normalizedBaseURL(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "ftp://example.com", "https://"])
    func rejects(input: String) {
        #expect(ConnectionConfiguration.normalizedBaseURL(from: input) == nil)
    }

    @Test func flagsPlainHTTP() {
        let http = ConnectionConfiguration(baseURL: URL(string: "http://kimai.local")!, auth: .bearer(token: "x"))
        let https = ConnectionConfiguration(baseURL: URL(string: "https://kimai.local")!, auth: .bearer(token: "x"))
        #expect(http.isInsecure)
        #expect(!https.isInsecure)
    }
}
