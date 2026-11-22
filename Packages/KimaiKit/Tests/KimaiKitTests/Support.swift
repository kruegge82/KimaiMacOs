import Foundation
@testable import KimaiKit

/// Records requests and answers them from a queue of canned responses.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Stub {
        var status = 200
        var body = "{}"
        var headers: [String: String] = [:]
        var error: Error?
    }

    private let lock = NSLock()
    private var stubs: [Stub]
    private var recorded: [URLRequest] = []

    init(_ stubs: [Stub]) {
        self.stubs = stubs
    }

    convenience init(status: Int = 200, body: String, headers: [String: String] = [:]) {
        self.init([Stub(status: status, body: body, headers: headers)])
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let stub: Stub = lock.withLock {
            recorded.append(request)
            return stubs.count > 1 ? stubs.removeFirst() : stubs[0]
        }
        if let error = stub.error { throw error }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        return (Data(stub.body.utf8), response)
    }
}

enum Fixture {
    static let vancouver = TimeZone(identifier: "America/Vancouver")!
    static let berlin = TimeZone(identifier: "Europe/Berlin")!

    static func client(
        _ transport: MockTransport, base: String = "https://kimai.example.com",
        auth: AuthMethod = .bearer(token: "secret"), timeZone: TimeZone = berlin
    ) -> KimaiClient {
        KimaiClient(
            configuration: ConnectionConfiguration(baseURL: URL(string: base)!, auth: auth),
            timeZone: timeZone, transport: transport)
    }

    static func body(of request: URLRequest) -> [String: Any] {
        guard let data = request.httpBody,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    static func date(_ string: String) -> Date {
        KimaiDate.parse(string)!
    }

    /// Collection format: related entities are plain ids.
    static let timesheetCollection = """
    [{"activity":2818,"project":50,"user":2,"tags":["urgent","web"],"id":751,
      "begin":"2026-12-04T09:08:00-0700","end":"2026-12-04T22:20:00-0700","duration":47520,"break":0,
      "description":"Hatter","exported":false,"billable":true,"metaFields":[]},
     {"activity":2124,"project":175,"user":2,"tags":[],"id":713,
      "begin":"2026-12-03T12:29:00-0700","end":"2026-12-04T01:02:00-0700","duration":45180,"break":0,
      "description":null,"exported":true,"billable":false,"metaFields":[]}]
    """

    /// Expanded format of `/timesheets/active`: nested objects, `end` is null.
    static let activeTimesheets = """
    [{"tags":[],"id":787,"begin":"2026-11-21T07:03:45-0700","end":null,"duration":0,"break":0,
      "user":{"id":2,"username":"user"},
      "activity":{"color-safe":"#FFC107","id":2276,
                  "project":{"id":189,"customer":{"id":11,"name":"Schamberger-Langosh"},"name":"Ad qui"},
                  "name":"Testing","visible":true},
      "project":{"color-safe":"#85144b","id":189,"customer":{"id":11,"name":"Schamberger-Langosh"},
                 "name":"Ad qui","visible":true,"globalActivities":true},
      "description":"Running task","exported":false,"billable":true}]
    """

    static let catalog = Catalog(
        customers: [
            Customer(id: 1, name: "Müller GmbH"),
            Customer(id: 2, name: "Acme Corp")
        ],
        projects: [
            Project(id: 10, name: "Webshop Relaunch", customerID: 1, color: "#ff0000"),
            Project(id: 11, name: "Wartung", customerID: 1, globalActivities: false),
            Project(id: 20, name: "Mobile App", customerID: 2),
            Project(id: 21, name: "Archiv", customerID: 2, visible: false)
        ],
        activities: [
            Activity(id: 100, name: "Entwicklung"),
            Activity(id: 101, name: "Besprechung"),
            Activity(id: 110, name: "Server-Updates", projectID: 11),
            Activity(id: 120, name: "Design", projectID: 20),
            Activity(id: 121, name: "Alt", projectID: 20, visible: false)
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_000_000))
}
