import Foundation
import Supabase

/// Stadt-Termine aus der Tabelle `city_events` des Backends.
public nonisolated struct CityEventClient: Sendable {
    private let client = Backend.client

    public init() {}

    nonisolated struct Row: Decodable, Sendable {
        let externalId: String
        let day: String?
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
            case title, summary, location, organizer, category, day
            case externalId = "external_id"
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case seriesNote = "series_note"
            case detailUrl = "detail_url"
        }
    }

    private static let columns = "external_id, day, title, starts_at, ends_at, summary, location, organizer, category, series_note, detail_url"

    public func events(on day: Date) async throws -> [StedeEvent] {
        let tenantID = try await Self.tenantID()
        let rows: [Row] = try await client.from("city_events")
            .select(Self.columns)
            .eq("tenant_id", value: tenantID).eq("day", value: IslandTime.isoDate(day)).is("deleted_at", value: nil)
            .order("starts_at").execute().value
        return rows.map(Self.event)
    }

    /// Alle Termine von `start` bis einschließlich `end` in einer Abfrage, nach Tag (ISO) gruppiert.
    public func events(from start: Date, through end: Date) async throws -> [String: [StedeEvent]] {
        let tenantID = try await Self.tenantID()
        let rows: [Row] = try await client.from("city_events")
            .select(Self.columns)
            .eq("tenant_id", value: tenantID)
            .gte("day", value: IslandTime.isoDate(start)).lte("day", value: IslandTime.isoDate(end))
            .is("deleted_at", value: nil)
            .order("starts_at").limit(2000).execute().value
        return Dictionary(grouping: rows, by: { $0.day ?? "" }).mapValues { $0.map(Self.event) }
    }

    private static func event(_ row: Row) -> StedeEvent {
        StedeEvent(
            id: Int(row.externalId) ?? row.externalId.hashValue, title: row.title, time: row.startsAt, endTime: row.endsAt,
            summary: row.summary, location: row.location, organizer: row.organizer, category: row.category,
            seriesNote: row.seriesNote, detailURL: row.detailUrl.flatMap(URL.init(string:))
        )
    }

    /// Die Mandanten-ID je Gemeinde einmal pro Start nachschlagen.
    private static let tenantLookup = TenantLookup()

    private static func tenantID() async throws -> UUID {
        try await tenantLookup.id()
    }
}

private actor TenantLookup {
    private var cached: [String: UUID] = [:]

    func id() async throws -> UUID {
        let slug = Backend.tenantSlug
        if let id = cached[slug] { return id }
        let tenant: Tenant = try await Backend.client.from("tenants").select("id, slug, name, municipality").eq("slug", value: slug).single().execute().value
        cached[slug] = tenant.id
        return tenant.id
    }
}
