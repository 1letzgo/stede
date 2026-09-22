import Foundation
import Supabase

/// Stadt-Termine aus der Tabelle `city_events` des Backends.
public nonisolated struct CityEventClient: Sendable {
    private let client = Backend.client

    public init() {}

    nonisolated struct Row: Decodable, Sendable {
        let externalId: String
        let title: String
        let startsAt: Date?
        let endsAt: Date?
        let summary: String
        let location: String?
        let organizer: String?
        let category: String?
        let seriesNote: String?
        let detailUrl: String?

        enum CodingKeys: String, CodingKey {
            case title, summary, location, organizer, category
            case externalId = "external_id"
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case seriesNote = "series_note"
            case detailUrl = "detail_url"
        }
    }

    public func events(on day: Date) async throws -> [StedeEvent] {
        let tenant: Tenant = try await client.from("tenants").select("id, slug, name, municipality").eq("slug", value: Backend.tenantSlug).single().execute().value
        let rows: [Row] = try await client.from("city_events")
            .select("external_id, title, starts_at, ends_at, summary, location, organizer, category, series_note, detail_url")
            .eq("tenant_id", value: tenant.id).eq("day", value: IslandTime.isoDate(day)).is("deleted_at", value: nil)
            .order("starts_at").execute().value
        return rows.map { row in
            StedeEvent(
                id: Int(row.externalId) ?? row.externalId.hashValue, title: row.title, time: row.startsAt, endTime: row.endsAt,
                summary: row.summary, location: row.location, organizer: row.organizer, category: row.category,
                seriesNote: row.seriesNote, detailURL: row.detailUrl.flatMap(URL.init(string:))
            )
        }
    }
}
