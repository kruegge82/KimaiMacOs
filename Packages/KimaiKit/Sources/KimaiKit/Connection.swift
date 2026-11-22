import Foundation

public enum AuthMethod: Hashable, Sendable {
    /// `Authorization: Bearer …` — API tokens of Kimai 2.14 and newer.
    case bearer(token: String)
    /// `X-AUTH-USER` / `X-AUTH-TOKEN` — API passwords of older Kimai versions.
    case legacy(username: String, token: String)

    public var token: String {
        switch self {
        case .bearer(let token), .legacy(_, let token): token
        }
    }
}

public struct ConnectionConfiguration: Hashable, Sendable {
    public var baseURL: URL
    public var auth: AuthMethod

    public init(baseURL: URL, auth: AuthMethod) {
        self.baseURL = baseURL
        self.auth = auth
    }

    /// Turns user input such as ` kimai.example.com/ ` or `https://x.org/kimai/api` into the
    /// base URL of the installation. Returns `nil` if no usable host remains.
    public static func normalizedBaseURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        for suffix in ["/api/doc", "/api"] where path.lowercased().hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path
        return components.url
    }

    /// Plain HTTP sends the token unencrypted; acceptable only for local test setups.
    public var isInsecure: Bool { baseURL.scheme?.lowercased() != "https" }
}

/// Minimal abstraction over `URLSession` so the client can be tested without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KimaiError.invalidResponse }
        return (data, http)
    }

    /// Session used for Kimai: no cookies (the API is stateless and a stored web session
    /// would change how Kimai authenticates), no response cache, short timeouts.
    public static func kimai() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

public struct Page<Item: Sendable>: Sendable {
    public var items: [Item]
    public var page: Int
    public var totalPages: Int
    public var totalCount: Int

    public init(items: [Item], page: Int, totalPages: Int, totalCount: Int) {
        self.items = items
        self.page = page
        self.totalPages = totalPages
        self.totalCount = totalCount
    }

    public var hasMore: Bool { page < totalPages }
}
