import Foundation
import Supabase

/// Geräte-Tokens für Push (Tabelle `push_tokens`, je Nutzer nur die eigenen). Den Versand
/// übernimmt die Edge Function `push-send`, ausgelöst von DB-Triggern bei neuen
/// Beitrittsanfragen, beantragten Gruppen, Terminen und Umfragen.
public nonisolated struct PushClient: Sendable {
    private let client = Backend.client

    public init() {}

    /// `sandbox` für Debug-Builds aus Xcode, sonst `production` (TestFlight, App Store).
    public func register(token: String, userID: UUID, sandbox: Bool, tenantID: UUID?) async throws {
        struct Row: Encodable {
            let token: String
            let user_id: UUID
            let platform: String
            let environment: String
            let tenant_id: UUID?
            let updated_at: Date
        }
        let row = Row(token: token, user_id: userID, platform: "ios", environment: sandbox ? "sandbox" : "production",
                      tenant_id: tenantID, updated_at: Date())
        try await client.from("push_tokens").upsert(row, onConflict: "token").execute()
    }

    /// Einstellungen des Nutzers; ohne Zeile ist alles an.
    public func settings(userID: UUID) async throws -> PushSettings {
        let rows: [PushSettings] = try await client.from("push_settings")
            .select("events, polls, admin, muted_communities").eq("user_id", value: userID).limit(1).execute().value
        return rows.first ?? PushSettings()
    }

    public func save(_ settings: PushSettings, userID: UUID) async throws {
        struct Row: Encodable {
            let user_id: UUID
            let events: Bool
            let polls: Bool
            let admin: Bool
            let muted_communities: [UUID]
            let updated_at: Date
        }
        let row = Row(user_id: userID, events: settings.events, polls: settings.polls, admin: settings.admin,
                      muted_communities: settings.mutedCommunities.sorted { $0.uuidString < $1.uuidString }, updated_at: Date())
        try await client.from("push_settings").upsert(row, onConflict: "user_id").execute()
    }

    /// Vor dem Abmelden: dieses Gerät bekommt keine Nachrichten des Kontos mehr.
    public func unregister(token: String) async throws {
        try await client.from("push_tokens").delete().eq("token", value: token).execute()
    }
}

/// Worüber jemand benachrichtigt werden will (`push_settings`); `push-send` filtert danach.
public nonisolated struct PushSettings: Codable, Hashable, Sendable {
    public var events = true
    public var polls = true
    /// Beitrittsanfragen und beantragte Gruppen.
    public var admin = true
    /// Stummgeschaltete Gruppen: keine Termine, Umfragen oder Anfragen von dort.
    public var mutedCommunities: Set<UUID> = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case events, polls, admin
        case mutedCommunities = "muted_communities"
    }
}
