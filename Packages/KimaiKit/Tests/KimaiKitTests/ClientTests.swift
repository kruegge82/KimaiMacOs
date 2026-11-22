import Foundation
import Testing
@testable import KimaiKit

@Suite struct ClientRequestTests {
    @Test func sendsBearerToken() async throws {
        let transport = MockTransport(body: #"{"version":"2.72.0","versionId":27200}"#)
        let version = try await Fixture.client(transport).version()
        #expect(version.version == "2.72.0")
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://kimai.example.com/api/version")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "X-AUTH-USER") == nil)
    }

    @Test func sendsLegacyHeadersAndKeepsSubdirectory() async throws {
        let transport = MockTransport(body: #"{"version":"1.30.0"}"#)
        let client = Fixture.client(
            transport, base: "https://example.com/kimai", auth: .legacy(username: "anna", token: "pw"))
        _ = try await client.version()
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://example.com/kimai/api/version")
        #expect(request.value(forHTTPHeaderField: "X-AUTH-USER") == "anna")
        #expect(request.value(forHTTPHeaderField: "X-AUTH-TOKEN") == "pw")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func listsTimesheetsWithPagingHeaders() async throws {
        let transport = MockTransport(
            body: Fixture.timesheetCollection,
            headers: ["X-Page": "2", "X-Total-Pages": "7", "X-Total-Count": "347"])
        let begin = Fixture.date("2026-11-16T00:00:00+0100")
        let page = try await Fixture.client(transport).timesheets(page: 2, size: 50, begin: begin, term: " shop ")
        #expect(page.items.count == 2)
        #expect(page.page == 2)
        #expect(page.totalPages == 7)
        #expect(page.totalCount == 347)
        #expect(page.hasMore)

        let url = try #require(transport.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(query == [
            "page": "2", "size": "50", "active": "0", "orderBy": "begin", "order": "DESC",
            "begin": "2026-11-16T00:00:00", "term": "shop"
        ])
    }

    @Test func pagingPastTheEndIsNotAnError() async throws {
        let transport = MockTransport(status: 404, body: #"{"code":404,"message":"Not Found"}"#)
        let page = try await Fixture.client(transport).timesheets(page: 3)
        #expect(page.items.isEmpty)
        #expect(!page.hasMore)
    }

    @Test func createsRunningTimerInProfileTimeZone() async throws {
        let transport = MockTransport(body: """
        {"activity":100,"project":10,"id":900,"begin":"2026-11-21T07:00:00-0700","end":null,"duration":0,
         "description":"Deploy","tags":["web"],"exported":false,"billable":true}
        """)
        let draft = TimesheetDraft(
            begin: Fixture.date("2026-11-21T15:00:00+0100"), projectID: 10, activityID: 100,
            description: "  Deploy ", tags: ["web", "urgent"])
        // Phoenix has no daylight saving time, so the expectation is stable: always UTC-7.
        let phoenix = try #require(TimeZone(identifier: "America/Phoenix"))
        let created = try await Fixture.client(transport, timeZone: phoenix).create(draft)
        #expect(created.id == 900)
        #expect(created.isRunning)

        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/api/timesheets")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = Fixture.body(of: request)
        // 15:00 in Berlin is 07:00 in Phoenix; Kimai reads the value in the profile zone.
        #expect(body["begin"] as? String == "2026-11-21T07:00:00")
        #expect(body["end"] == nil)
        #expect(body["project"] as? Int == 10)
        #expect(body["activity"] as? Int == 100)
        #expect(body["description"] as? String == "Deploy")
        #expect(body["tags"] as? String == "web,urgent")
        #expect(body["billable"] == nil)
    }

    @Test func updateSendsOnlyChangedFields() async throws {
        let transport = MockTransport(body: Fixture.activeTimesheets.dropFirst().dropLast().description)
        let client = Fixture.client(transport)

        _ = try await client.update(id: 787, changes: TimesheetChanges(description: " New text "))
        var request = try #require(transport.requests.last)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/api/timesheets/787")
        // A description-only edit must not touch times, booking, tags or the billable flag.
        #expect(Fixture.body(of: request) as? [String: String] == ["description": "New text"])

        _ = try await client.update(id: 787, changes: TimesheetChanges(
            end: Fixture.date("2026-11-21T16:30:00+0100"), booking: Booking(projectID: 10, activityID: 100),
            tags: [], billable: false))
        request = try #require(transport.requests.last)
        let body = Fixture.body(of: request)
        #expect(Set(body.keys) == ["end", "project", "activity", "tags", "billable"])
        #expect(body["end"] as? String == "2026-11-21T16:30:00")
        #expect(body["project"] as? Int == 10)
        #expect(body["activity"] as? Int == 100)
        #expect(body["tags"] as? String == "")
        #expect(body["billable"] as? Bool == false)
        #expect(TimesheetChanges().isEmpty)
        #expect(!TimesheetChanges(description: "").isEmpty)
    }

    @Test func stopRestartDuplicateDeleteUseExpectedEndpoints() async throws {
        let entity = """
        {"activity":100,"project":10,"id":5,"begin":"2026-11-21T07:00:00+0100","end":"2026-11-21T08:00:00+0100",
         "duration":3600,"description":null,"tags":[]}
        """
        let transport = MockTransport(body: entity)
        let client = Fixture.client(transport)
        _ = try await client.stop(id: 5)
        _ = try await client.restart(id: 5)
        _ = try await client.duplicate(id: 5)
        _ = try await client.stop(id: 5, at: Fixture.date("2026-11-21T07:30:00+0100"))
        try await client.delete(id: 5)

        let requests = transport.requests
        #expect(requests.map(\.httpMethod) == ["PATCH", "PATCH", "PATCH", "PATCH", "DELETE"])
        #expect(requests.map { $0.url!.path } == [
            "/api/timesheets/5/stop", "/api/timesheets/5/restart", "/api/timesheets/5/duplicate",
            "/api/timesheets/5", "/api/timesheets/5"
        ])
        #expect(requests[0].httpBody == nil)
        #expect(Fixture.body(of: requests[1])["copy"] as? String == "all")
        #expect(Fixture.body(of: requests[3]) as? [String: String] == ["end": "2026-11-21T07:30:00"])
    }
}

@Suite struct ClientErrorTests {
    @Test func mapsStatusCodes() async {
        for (status, expected) in [(401, KimaiError.unauthorized), (403, .forbidden), (404, .notFound)] {
            let transport = MockTransport(status: status, body: #"{"message":"x"}"#)
            await #expect(throws: expected) { try await Fixture.client(transport).version() }
        }
        let transport = MockTransport(status: 500, body: #"{"code":500,"message":"Boom"}"#)
        await #expect(throws: KimaiError.server(status: 500, message: "Boom")) {
            try await Fixture.client(transport).version()
        }
    }

    @Test func extractsValidationMessages() async {
        let body = """
        {"code":400,"message":"Validation Failed","errors":{"errors":["Overlapping records"],
         "children":{"begin":{},"end":{"errors":["End date must not be earlier then start date."]},
                     "project":{"errors":["This value should not be null."]},"tags":[]}}}
        """
        let transport = MockTransport(status: 400, body: body)
        await #expect(throws: KimaiError.validation(message: "Validation Failed", fields: [
            "": ["Overlapping records"],
            "end": ["End date must not be earlier then start date."],
            "project": ["This value should not be null."]
        ])) {
            try await Fixture.client(transport).create(TimesheetDraft())
        }
    }

    @Test func htmlInsteadOfJSONIsAnInvalidResponse() async {
        let transport = MockTransport(body: "<!doctype html><html><body>Login</body></html>")
        await #expect(throws: KimaiError.invalidResponse) { try await Fixture.client(transport).version() }
    }

    @Test func mapsTransportErrors() async {
        let cases: [(URLError.Code, KimaiError)] = [
            (.notConnectedToInternet, .offline), (.timedOut, .timeout), (.cannotFindHost, .cannotReachHost),
            (.serverCertificateUntrusted, .insecureConnection), (.cancelled, .cancelled)
        ]
        for (code, expected) in cases {
            let transport = MockTransport([.init(error: URLError(code))])
            await #expect(throws: expected) { try await Fixture.client(transport).version() }
        }
        #expect(KimaiError.offline.isTransient)
        #expect(KimaiError.server(status: 503, message: nil).isTransient)
        #expect(!KimaiError.unauthorized.isTransient)
        #expect(KimaiError.from(CancellationError()) == .cancelled)
    }
}

/// Talks to the public Kimai demo. Enable with `KIMAI_LIVE_TEST=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["KIMAI_LIVE_TEST"] == "1"))
struct LiveDemoTests {
    func makeClient() async throws -> KimaiClient {
        let configuration = ConnectionConfiguration(
            baseURL: URL(string: "https://demo.kimai.org")!, auth: .bearer(token: "token_user"))
        var client = KimaiClient(configuration: configuration)
        if let zone = try await client.currentUser().timeZone { client.timeZone = zone }
        return client
    }

    @Test func readsServerState() async throws {
        let client = try await makeClient()
        #expect(!(try await client.version()).version.isEmpty)
        #expect((try await client.timesheetConfig()).activeEntriesHardLimit >= 0)
        let catalog = try await client.catalog()
        #expect(!catalog.projects.isEmpty)
        #expect(!catalog.activities.isEmpty)
        let page = try await client.timesheets(page: 1, size: 5)
        #expect(page.items.count <= 5)
        #expect(page.totalCount >= page.items.count)
        _ = try await client.activeTimesheets()
        _ = try await client.recentTimesheets(size: 5)
    }

    @Test func fullTimerLifecycle() async throws {
        let client = try await makeClient()
        let catalog = try await client.catalog()
        let project = try #require(catalog.projectGroups.first?.projects.first)
        let activity = try #require(catalog.activities(forProjectID: project.id).first)

        let begin = Date().addingTimeInterval(-600)
        let started = try await client.create(TimesheetDraft(
            begin: begin, projectID: project.id, activityID: activity.id, description: "KimaiKit live test"))
        #expect(started.isRunning)
        // The server must have understood the time in the profile zone.
        #expect(abs(started.begin.timeIntervalSince(begin)) < 61)
        #expect(try await client.activeTimesheets().contains { $0.id == started.id })

        let renamed = try await client.update(
            id: started.id, changes: TimesheetChanges(description: "KimaiKit live test 2"))
        #expect(renamed.description == "KimaiKit live test 2")
        #expect(renamed.isRunning)

        let stopAt = Date().addingTimeInterval(-300)
        let stopped = try await client.stop(id: started.id, at: stopAt)
        #expect(!stopped.isRunning)
        #expect(abs((stopped.end ?? .distantPast).timeIntervalSince(stopAt)) < 61)

        let restarted = try await client.restart(id: started.id)
        #expect(restarted.isRunning)
        #expect(restarted.projectID == project.id)
        let finished = try await client.stop(id: restarted.id)
        #expect(!finished.isRunning)

        try await client.delete(id: restarted.id)
        try await client.delete(id: started.id)
        await #expect(throws: KimaiError.notFound) { try await client.timesheet(id: started.id) }
    }
}
