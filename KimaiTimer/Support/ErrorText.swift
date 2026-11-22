import KimaiKit

/// Explains a failure in the user's language and says what to do about it.
enum ErrorText {
    static func message(for error: KimaiError) -> String {
        switch error {
        case .invalidURL:
            L("The server address is not valid.")
        case .unauthorized:
            L("Kimai rejected the credentials. Check the API token in Settings.")
        case .forbidden:
            L("Your Kimai account is not allowed to do this.")
        case .notFound:
            L("Kimai could not find this record. It may have been deleted.")
        case .validation(let message, let fields):
            validation(message: message, fields: fields)
        case .server(let status, let message):
            if let message, !message.isEmpty {
                status > 0 ? L("Kimai reported an error (%d): %@", status, message) : message
            } else {
                L("Kimai reported an error (%d).", status)
            }
        case .offline:
            L("This Mac is offline. Timers can only be started, stopped or changed while Kimai is reachable.")
        case .timeout:
            L("Kimai did not answer in time.")
        case .cannotReachHost:
            L("The Kimai server cannot be reached. Check the address and your network.")
        case .insecureConnection:
            L("A secure connection to the server could not be established.")
        case .invalidResponse:
            L("The server did not answer like Kimai. Check the server address.")
        case .cancelled:
            L("The request was cancelled.")
        }
    }

    private static func validation(message: String, fields: [String: [String]]) -> String {
        let details = fields
            .sorted { $0.key < $1.key }
            .map { field, messages in
                let text = messages.joined(separator: " ")
                return field.isEmpty ? text : "\(fieldName(field)): \(text)"
            }
        guard !details.isEmpty else { return L("Kimai did not accept the entry: %@", message) }
        return L("Kimai did not accept the entry: %@", details.joined(separator: " "))
    }

    private static func fieldName(_ field: String) -> String {
        switch field {
        case "begin": L("Start")
        case "end": L("End")
        case "project": L("Project")
        case "activity": L("Activity")
        case "description": L("Description")
        case "tags": L("Tags")
        case "duration": L("Duration")
        default: field
        }
    }
}
