import Foundation

/// Typed access to the parts of the Kimai REST API a time tracking client needs.
public struct KimaiClient: Sendable {
    public let configuration: ConnectionConfiguration
    /// Zone in which Kimai interprets submitted times (the user's profile zone).
    public var timeZone: TimeZone
    private let transport: any HTTPTransport

    public init(
        configuration: ConnectionConfiguration,
        timeZone: TimeZone = .current,
        transport: any HTTPTransport = URLSession.kimai()
    ) {
        self.configuration = configuration
        self.timeZone = timeZone
        self.transport = transport
    }

    // MARK: Server

    public func version() async throws -> ServerVersion {
        try await get("version")
    }

    public func currentUser() async throws -> KimaiUser {
        try await get("users/me")
    }

    public func timesheetConfig() async throws -> TimesheetConfig {
        try await get("config/timesheet")
    }

    // MARK: Master data

    public func customers() async throws -> [Customer] {
        try await get("customers", query: [URLQueryItem(name: "visible", value: "1")])
    }

    public func projects() async throws -> [Project] {
        try await get("projects", query: [URLQueryItem(name: "visible", value: "1")])
    }

    public func activities() async throws -> [Activity] {
        try await get("activities", query: [URLQueryItem(name: "visible", value: "1")])
    }

    public func catalog(now: Date = Date()) async throws -> Catalog {
        async let customers = customers()
        async let projects = projects()
        async let activities = activities()
        return try await Catalog(
            customers: customers, projects: projects, activities: activities, fetchedAt: now)
    }

    // MARK: Time records

    public func activeTimesheets() async throws -> [Timesheet] {
        try await get("timesheets/active")
    }

    public func recentTimesheets(size: Int = 20) async throws -> [Timesheet] {
        try await get("timesheets/recent", query: [URLQueryItem(name: "size", value: String(size))])
    }

    /// Finished records, newest first.
    public func timesheets(
        page: Int = 1, size: Int = 50, begin: Date? = nil, end: Date? = nil, term: String? = nil
    ) async throws -> Page<Timesheet> {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "active", value: "0"),
            URLQueryItem(name: "orderBy", value: "begin"),
            URLQueryItem(name: "order", value: "DESC")
        ]
        if let begin {
            query.append(URLQueryItem(name: "begin", value: KimaiDate.format(begin, timeZone: timeZone)))
        }
        if let end {
            query.append(URLQueryItem(name: "end", value: KimaiDate.format(end, timeZone: timeZone)))
        }
        if let term = term?.trimmingCharacters(in: .whitespacesAndNewlines), !term.isEmpty {
            query.append(URLQueryItem(name: "term", value: term))
        }
        do {
            let (data, response) = try await perform(makeRequest("GET", "timesheets", query: query))
            let items: [Timesheet] = try decode(data)
            let header = { (name: String) in response.value(forHTTPHeaderField: name).flatMap(Int.init) }
            return Page(
                items: items,
                page: header("X-Page") ?? page,
                totalPages: header("X-Total-Pages") ?? (items.count < size ? page : page + 1),
                totalCount: header("X-Total-Count") ?? items.count)
        } catch KimaiError.notFound where page > 1 {
            // Kimai answers 404 when paging past the last page.
            return Page(items: [], page: page, totalPages: page - 1, totalCount: 0)
        }
    }

    public func timesheet(id: Int) async throws -> Timesheet {
        try await get("timesheets/\(id)")
    }

    /// Creates a record. Without `end` this starts a running timer; Kimai stops other
    /// running timers itself if its hard limit requires that.
    public func create(_ draft: TimesheetDraft) async throws -> Timesheet {
        try await send("POST", "timesheets", body: payload(for: draft, includeEnd: true))
    }

    /// Changes only the given fields of a record.
    public func update(id: Int, changes: TimesheetChanges) async throws -> Timesheet {
        let payload = TimesheetPayload(
            begin: changes.begin.map { KimaiDate.format($0, timeZone: timeZone) },
            end: changes.end.map { KimaiDate.format($0, timeZone: timeZone) },
            project: changes.booking?.projectID,
            activity: changes.booking?.activityID,
            description: changes.description?.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: changes.tags?.joined(separator: ","),
            billable: changes.billable)
        return try await send("PATCH", "timesheets/\(id)", body: payload)
    }

    public func stop(id: Int) async throws -> Timesheet {
        try await send("PATCH", "timesheets/\(id)/stop", body: Optional<TimesheetPayload>.none)
    }

    /// Stops a running timer at a moment in the past, e.g. when the user walked away.
    public func stop(id: Int, at end: Date) async throws -> Timesheet {
        try await send(
            "PATCH", "timesheets/\(id)",
            body: TimesheetPayload(end: KimaiDate.format(end, timeZone: timeZone)))
    }

    /// Starts a new timer with the same project, activity, description and tags.
    public func restart(id: Int) async throws -> Timesheet {
        try await send("PATCH", "timesheets/\(id)/restart", body: RestartPayload(copy: "all"))
    }

    public func duplicate(id: Int) async throws -> Timesheet {
        try await send("PATCH", "timesheets/\(id)/duplicate", body: Optional<TimesheetPayload>.none)
    }

    public func delete(id: Int) async throws {
        _ = try await perform(makeRequest("DELETE", "timesheets/\(id)"))
    }

    // MARK: Plumbing

    struct TimesheetPayload: Encodable {
        var begin: String?
        var end: String?
        var project: Int?
        var activity: Int?
        var description: String?
        var tags: String?
        var billable: Bool?
    }

    struct RestartPayload: Encodable {
        let copy: String
    }

    private func payload(for draft: TimesheetDraft, includeEnd: Bool) -> TimesheetPayload {
        TimesheetPayload(
            begin: KimaiDate.format(draft.begin, timeZone: timeZone),
            end: includeEnd ? draft.end.map { KimaiDate.format($0, timeZone: timeZone) } : nil,
            project: draft.projectID,
            activity: draft.activityID,
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: draft.tags.joined(separator: ","),
            billable: draft.billable)
    }

    func makeRequest(_ method: String, _ path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw KimaiError.invalidURL
        }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + "/api/" + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw KimaiError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch configuration.auth {
        case .bearer(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .legacy(let username, let token):
            request.setValue(username, forHTTPHeaderField: "X-AUTH-USER")
            request.setValue(token, forHTTPHeaderField: "X-AUTH-TOKEN")
        }
        return request
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        let (data, _) = try await perform(makeRequest("GET", path, query: query))
        return try decode(data)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, body: Body?
    ) async throws -> Response {
        var request = try makeRequest(method, path)
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, _) = try await perform(request)
        return try decode(data)
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw KimaiError.invalidResponse
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw KimaiError.from(error)
        }
        guard !(200..<300).contains(response.statusCode) else { return (data, response) }

        let body = try? JSONDecoder().decode(KimaiErrorBody.self, from: data)
        switch response.statusCode {
        case 401:
            throw KimaiError.unauthorized
        case 403:
            throw KimaiError.forbidden
        case 404:
            throw KimaiError.notFound
        case 400, 422:
            throw KimaiError.validation(
                message: body?.message ?? "Validation Failed", fields: body?.fieldErrors ?? [:])
        default:
            throw KimaiError.server(status: response.statusCode, message: body?.message)
        }
    }
}
