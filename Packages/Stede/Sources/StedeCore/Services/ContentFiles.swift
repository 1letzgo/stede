import Foundation
import Supabase

/// Statische Inhalte als Dateien im öffentlichen Bucket `content` (Tabelle `content_files`):
/// Bushaltestellen, Straßenliste der Abfuhr und die Offline-Karte. Beim Start werden nur
/// geänderte Dateien geladen; die Leser nehmen den lokalen Stand, sonst das Bundle.
/// Wie bei `ContentSync` gilt ein neuer Stand ab dem nächsten Start.
public actor ContentFiles {
    public static let shared = ContentFiles()

    nonisolated struct Row: Decodable, Sendable {
        let name: String
        let path: String
        let updatedAt: Date
        enum CodingKeys: String, CodingKey {
            case name, path
            case updatedAt = "updated_at"
        }
    }

    private static func folder(_ slug: String) -> URL { Tenants.contentFolder(slug).appendingPathComponent("files", isDirectory: true) }
    private static func file(_ name: String, _ slug: String) -> URL { folder(slug).appendingPathComponent("\(name).json") }
    private static func manifestURL(_ slug: String) -> URL { folder(slug).appendingPathComponent("manifest.json") }

    /// Lokal geladener Stand einer Datei der aktuellen Gemeinde, sonst nil (dann gilt das Bundle).
    public nonisolated static func data(_ name: String) -> Data? {
        try? Data(contentsOf: file(name, Tenants.currentSlug))
    }

    /// Ohne Angabe die aktuelle Gemeinde; beim Wechsel die neue, bevor sie gilt.
    /// Liefert true, wenn eine Datei neu geladen wurde.
    @discardableResult
    public func sync(slug: String = Tenants.currentSlug) async -> Bool {
        do {
            let tenant: Tenant = try await Backend.client.from("tenants").select("id, slug, name, municipality")
                .eq("slug", value: slug).single().execute().value
            let rows: [Row] = try await Backend.client.from("content_files").select("name, path, updated_at")
                .eq("tenant_id", value: tenant.id).execute().value
            var manifest = (try? JSONDecoder().decode([String: Date].self, from: Data(contentsOf: Self.manifestURL(slug)))) ?? [:]
            let before = manifest
            try FileManager.default.createDirectory(at: Self.folder(slug), withIntermediateDirectories: true)
            for row in rows where manifest[row.name] != row.updatedAt || !FileManager.default.fileExists(atPath: Self.file(row.name, slug).path) {
                let url = Backend.url.appendingPathComponent("storage/v1/object/public/content/\(row.path)")
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      (try? JSONSerialization.jsonObject(with: data)) != nil else { continue }
                try data.write(to: Self.file(row.name, slug), options: .atomic)
                manifest[row.name] = row.updatedAt
            }
            guard manifest != before else { return false }
            try JSONEncoder().encode(manifest).write(to: Self.manifestURL(slug), options: .atomic)
            return true
        } catch {
            // Offline oder Backend nicht erreichbar: der letzte Stand bleibt.
            return false
        }
    }
}
