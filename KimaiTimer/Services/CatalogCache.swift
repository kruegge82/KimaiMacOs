import Foundation
import KimaiKit

/// Keeps the last known customers, projects and activities on disk so the app is usable
/// immediately after launch and while Kimai is unreachable.
struct CatalogCache {
    let fileURL: URL?

    private struct Envelope: Codable {
        let server: String
        let catalog: Catalog
    }

    init(fileName: String = "catalog.json") {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        fileURL = directory?
            .appendingPathComponent("KimaiTimer", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    func load(server: String) -> Catalog? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.server == server
        else { return nil }
        return envelope.catalog
    }

    func save(_ catalog: Catalog, server: String) {
        guard let fileURL, let data = try? JSONEncoder().encode(Envelope(server: server, catalog: catalog)) else {
            return
        }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
