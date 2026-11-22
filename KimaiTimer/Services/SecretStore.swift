import Foundation

/// Where the API token is kept. The app uses the Keychain; previews and UI snapshots use memory.
protocol SecretStore {
    func read(account: String) -> String?
    func write(_ value: String, account: String) throws
    func delete(account: String)
}

extension KeychainStore: SecretStore {}

final class MemorySecretStore: SecretStore {
    private var values: [String: String]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func read(account: String) -> String? { values[account] }
    func write(_ value: String, account: String) throws { values[account] = value }
    func delete(account: String) { values[account] = nil }
}
