import Foundation
import Supabase

/// Delta-Sync der Inhalte aus dem Backend: Orte je Verzeichnis und Stadt-Termine.
/// Das Bundle liefert den Erststand, das Backend ersetzt ihn Verzeichnis für
/// Verzeichnis, sobald einmal ein vollständiger Stand geladen wurde.
public actor ContentSync {
    public static let shared = ContentSync()

    private let client = Backend.client
    private let fileManager = FileManager.default
    private var tenantIDs: [String: UUID] = [:]

    private func file(_ name: String, _ slug: String) -> URL { Tenants.contentFolder(slug).appendingPathComponent("\(name).json") }

    /// Zeile aus `places`.
    nonisolated struct PlaceRow: Codable, Sendable {
        let externalId: String
        let directory: String
        let kind: String
        let name: String
        let teaser: String?
        let street: String?
        let phone: String?
        let email: String?
        let website: String?
        let hours: String?
        let restDay: String?
        let seasonNote: String?
        let imageCredit: String?
        let extraLinkTitle: String?
        let extraLinkUrl: String?
        let features: [String]
        let lat: Double?
        let lon: Double?
        let sortOrder: Int
        let updatedAt: Date
        let deletedAt: Date?

        enum CodingKeys: String, CodingKey {
            case directory, kind, name, teaser, street, phone, email, website, hours, features, lat, lon
            case externalId = "external_id"
            case restDay = "rest_day"
            case seasonNote = "season_note"
            case imageCredit = "image_credit"
            case extraLinkTitle = "extra_link_title"
            case extraLinkUrl = "extra_link_url"
            case sortOrder = "sort_order"
            case updatedAt = "updated_at"
            case deletedAt = "deleted_at"
        }
    }

    nonisolated struct DirectoryRow: Codable, Sendable {
        let directory: String
        let source: String
        let fetchedAt: String
        enum CodingKeys: String, CodingKey {
            case directory, source
            case fetchedAt = "fetched_at"
        }
    }

    /// Lokal gehaltener Stand eines Verzeichnisses.
    nonisolated struct Snapshot: Codable, Sendable {
        var source: String
        var fetchedAt: String
        var cursor: Date
        var places: [String: PlaceRow]
    }

    // MARK: Lesen

    /// Verzeichnis aus dem lokalen Stand, sonst nil (dann gilt das Bundle).
    public nonisolated static func directory(_ name: String) -> GastroDirectory? {
        let url = Tenants.contentFolder().appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        let places = snapshot.places.values
            .filter { $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            .map(GastroPlace.init(row:))
        return GastroDirectory(source: snapshot.source, fetchedAt: snapshot.fetchedAt, places: places)
    }

    public nonisolated static func bikeDirectory() -> BikeRentalDirectory? {
        let url = Tenants.contentFolder().appendingPathComponent("bikes.json")
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return nil }
        let providers = snapshot.places.values
            .filter { $0.deletedAt == nil }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            .map { row in
                BikeRentalProvider(
                    id: row.externalId, name: row.name, teaser: row.teaser, phone: row.phone, email: row.email, website: row.website,
                    features: row.features,
                    stations: [BikeRentalStation(label: Tenants.current.municipality, street: row.street ?? "", latitude: row.lat ?? 0, longitude: row.lon ?? 0)]
                )
            }
        return BikeRentalDirectory(source: snapshot.source, fetchedAt: snapshot.fetchedAt, providers: providers)
    }

    // MARK: Sync

    public static let directories = ["gastro", "health", "leisure", "sights", "playgrounds", "trips", "bikes", "volunteer"]

    /// Beim Start und bei Pull-to-Refresh: alle Verzeichnisse nachziehen — ohne Angabe
    /// für die aktuelle Gemeinde, beim Wechsel für die neue, bevor sie gilt.
    public func syncAll(slug: String = Tenants.currentSlug) async {
        do {
            if tenantIDs[slug] == nil {
                let tenant: Tenant = try await client.from("tenants").select("id, slug, name, municipality").eq("slug", value: slug).single().execute().value
                tenantIDs[slug] = tenant.id
            }
            guard let tenantID = tenantIDs[slug] else { return }
            let directories: [DirectoryRow] = try await client.from("place_directories").select("directory, source, fetched_at").eq("tenant_id", value: tenantID).execute().value
            for meta in directories where Self.directories.contains(meta.directory) {
                try await sync(directory: meta, tenantID: tenantID, slug: slug)
            }
        } catch {
            // Offline oder Backend nicht erreichbar: der letzte Stand bleibt.
        }
    }

    private func sync(directory meta: DirectoryRow, tenantID: UUID, slug: String) async throws {
        var snapshot = loadSnapshot(meta.directory, slug) ?? Snapshot(source: meta.source, fetchedAt: meta.fetchedAt, cursor: .distantPast, places: [:])
        let rows: [PlaceRow] = try await client.from("places")
            .select("external_id, directory, kind, name, teaser, street, phone, email, website, hours, rest_day, season_note, image_credit, extra_link_title, extra_link_url, features, lat, lon, sort_order, updated_at, deleted_at")
            .eq("tenant_id", value: tenantID).eq("directory", value: meta.directory)
            .gt("updated_at", value: snapshot.cursor.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            .order("updated_at").limit(1000).execute().value
        guard !rows.isEmpty || snapshot.cursor == .distantPast else { return }
        for row in rows { snapshot.places[row.externalId] = row }
        snapshot.cursor = rows.map(\.updatedAt).max() ?? snapshot.cursor
        snapshot.source = meta.source
        snapshot.fetchedAt = meta.fetchedAt
        try fileManager.createDirectory(at: Tenants.contentFolder(slug), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: file(meta.directory, slug), options: .atomic)
    }

    private func loadSnapshot(_ name: String, _ slug: String) -> Snapshot? {
        guard let data = try? Data(contentsOf: file(name, slug)) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}

extension GastroPlace {
    /// Aus einer Backend-Zeile — gleiche Felder wie das Bundle-JSON.
    nonisolated init(row: ContentSync.PlaceRow) {
        self.init(
            id: row.externalId, name: row.name, category: row.kind, teaser: row.teaser, street: row.street,
            phone: row.phone, email: row.email, website: row.website, detailURL: nil,
            hours: row.hours, restDay: row.restDay, seasonNote: row.seasonNote, imageCredit: row.imageCredit,
            extraLinkTitle: row.extraLinkTitle, extraLinkURL: row.extraLinkUrl, latitude: row.lat, longitude: row.lon
        )
    }
}
