import Foundation

/// Everything that can go wrong while talking to Kimai, reduced to cases the UI can explain.
public enum KimaiError: Error, Equatable, Sendable {
    /// The server URL could not be turned into a valid request.
    case invalidURL
    /// 401: wrong or missing credentials.
    case unauthorized
    /// 403: the account lacks the permission for this action.
    case forbidden
    /// 404: record or endpoint does not exist (any more).
    case notFound
    /// 400/422: Kimai rejected the submitted values.
    case validation(message: String, fields: [String: [String]])
    /// Any other HTTP error status.
    case server(status: Int, message: String?)
    /// This Mac has no network connection.
    case offline
    case timeout
    /// DNS failure or connection refused.
    case cannotReachHost
    /// TLS or App Transport Security refused the connection.
    case insecureConnection
    /// The answer was not the JSON a Kimai API would send (usually a wrong URL).
    case invalidResponse
    case cancelled

    /// `true` for failures that are likely to disappear without user action.
    public var isTransient: Bool {
        switch self {
        case .offline, .timeout, .cannotReachHost, .cancelled: true
        case .server(let status, _): status >= 500
        default: false
        }
    }

    public static func from(_ error: Error) -> KimaiError {
        if let kimai = error as? KimaiError { return kimai }
        if error is CancellationError { return .cancelled }
        if error is DecodingError { return .invalidResponse }
        guard let urlError = error as? URLError else {
            return .server(status: 0, message: error.localizedDescription)
        }
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timeout
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .cannotReachHost
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return .insecureConnection
        case .badURL, .unsupportedURL:
            return .invalidURL
        default:
            return .server(status: 0, message: urlError.localizedDescription)
        }
    }
}

/// Shape of Kimai's error bodies:
/// `{"code":400,"message":"Validation Failed","errors":{"errors":[…],"children":{"end":{"errors":[…]}}}}`
struct KimaiErrorBody: Decodable {
    struct FormErrors: Decodable {
        struct Child: Decodable {
            let errors: [String]?
        }
        let errors: [String]?
        let children: [String: Child]?

        private enum CodingKeys: String, CodingKey { case errors, children }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            errors = try? c.decodeIfPresent([String].self, forKey: .errors)
            // Children without errors are serialised as `{}` or `[]`; tolerate both.
            let lossy = try? c.decodeIfPresent([String: LossyChild].self, forKey: .children)
            children = lossy?.mapValues { Child(errors: $0.errors) }
        }
    }

    struct LossyChild: Decodable {
        let errors: [String]?
        private enum CodingKeys: String, CodingKey { case errors }
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
                errors = nil
                return
            }
            errors = try? c.decodeIfPresent([String].self, forKey: .errors)
        }
    }

    let message: String?
    let errors: FormErrors?

    private enum CodingKeys: String, CodingKey { case message, errors }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        errors = try? c.decodeIfPresent(FormErrors.self, forKey: .errors)
    }

    var fieldErrors: [String: [String]] {
        var result: [String: [String]] = [:]
        if let general = errors?.errors, !general.isEmpty { result[""] = general }
        for (field, child) in errors?.children ?? [:] {
            if let messages = child.errors, !messages.isEmpty { result[field] = messages }
        }
        return result
    }
}
