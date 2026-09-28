import Foundation

/// Letzter Stand der Gruppen-Bereiche auf der Platte — Gruppenliste, Mitgliedschaften,
/// „Meine Aufgaben“, Gruppenseiten. Die Ansichten zeigen ihn sofort und laden im
/// Hintergrund nach; bei Fehlern bleibt er stehen. Abgelegt je Gemeinde und Nutzer
/// in `Application Support/community/<gemeinde>/<nutzer>/<name>.json` (ohne Anmeldung
/// `anon`); beim Abmelden löscht `clear(userID:)` den Ordner des Nutzers.
public nonisolated enum CommunityCache {
    private static func folder(userID: UUID?, slug: String = Tenants.currentSlug) -> URL {
        CacheMaintenance.directory("community")
            .appendingPathComponent(slug, isDirectory: true)
            .appendingPathComponent(userID?.uuidString.lowercased() ?? "anon", isDirectory: true)
    }

    private static func file(_ name: String, userID: UUID?) -> URL {
        folder(userID: userID).appendingPathComponent("\(name).json")
    }

    public static func load<T: Decodable>(_ type: T.Type, _ name: String, userID: UUID?) -> T? {
        guard let data = try? Data(contentsOf: file(name, userID: userID)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func save<T: Encodable>(_ value: T, _ name: String, userID: UUID?) {
        let url = file(name, userID: userID)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            // Nur ein Zwischenspeicher: ohne ihn lädt die Ansicht eben aus dem Netz.
        }
    }

    /// Nach dem Abmelden: alles dieses Nutzers in allen Gemeinden entfernen.
    public static func clear(userID: UUID) {
        let manager = FileManager.default
        let base = CacheMaintenance.directory("community")
        let slugs = (try? manager.contentsOfDirectory(atPath: base.path)) ?? []
        for slug in slugs {
            try? manager.removeItem(at: folder(userID: userID, slug: slug))
        }
    }
}
