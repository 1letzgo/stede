import Foundation
import Supabase

/// Alle Zugriffe auf den Community-Teil des Backends. RLS entscheidet, was
/// der angemeldete Nutzer sieht — der Client filtert nur nach Mandant.
public nonisolated struct CommunityClient: Sendable {
    private let client: SupabaseClient

    public init(client: SupabaseClient = Backend.client) {
        self.client = client
    }


    // MARK: Mandant

    public func tenant(slug: String = Backend.tenantSlug) async throws -> Tenant {
        try await client.from("tenants").select("id, slug, name, municipality").eq("slug", value: slug).single().execute().value
    }

    public func isTenantAdmin(tenantID: UUID) async throws -> Bool {
        let rows: [[String: String]] = try await client.from("tenant_admins")
            .select("tenant_id").eq("tenant_id", value: tenantID).execute().value
        return !rows.isEmpty
    }

    // MARK: Profil

    public func myProfile(userID: UUID) async throws -> Profile {
        try await client.from("profiles").select().eq("user_id", value: userID).single().execute().value
    }

    public func updateDisplayName(userID: UUID, name: String) async throws {
        try await client.from("profiles").update(["display_name": name]).eq("user_id", value: userID).execute()
    }

    // MARK: Communities

    private static let communityColumns = "id, tenant_id, name, description, visibility, join_policy, status, invite_code, logo_path, created_by, created_at, member_count"

    /// Alle sichtbaren Communities des Mandanten: gelistete plus eigene.
    public func communities(tenantID: UUID) async throws -> [Community] {
        try await client.from("v_community_overview").select(Self.communityColumns)
            .eq("tenant_id", value: tenantID).order("name").execute().value
    }

    public func community(id: UUID) async throws -> Community {
        try await client.from("v_community_overview").select(Self.communityColumns).eq("id", value: id).single().execute().value
    }

    public func communityByInvite(code: String) async throws -> Community? {
        let rows: [Community] = try await client.from("v_community_overview").select(Self.communityColumns)
            .eq("invite_code", value: code).limit(1).execute().value
        return rows.first
    }

    public func createCommunity(tenantID: UUID, name: String, description: String, visibility: CommunityVisibility, joinPolicy: CommunityJoinPolicy, userID: UUID) async throws -> Community {
        struct Draft: Encodable {
            let tenant_id: UUID; let name: String; let description: String
            let visibility: CommunityVisibility; let join_policy: CommunityJoinPolicy; let created_by: UUID
        }
        let created: Community = try await client.from("communities")
            .insert(Draft(tenant_id: tenantID, name: name, description: description, visibility: visibility, join_policy: joinPolicy, created_by: userID))
            .select("id, tenant_id, name, description, visibility, join_policy, status, invite_code, logo_path, created_by, created_at").single().execute().value
        return created
    }

    public func updateCommunity(id: UUID, name: String, description: String, visibility: CommunityVisibility, joinPolicy: CommunityJoinPolicy, logoPath: String?) async throws {
        struct Patch: Encodable { let name: String; let description: String; let visibility: CommunityVisibility; let join_policy: CommunityJoinPolicy; let logo_path: String? }
        try await client.from("communities").update(Patch(name: name, description: description, visibility: visibility, join_policy: joinPolicy, logo_path: logoPath)).eq("id", value: id).execute()
    }

    public func setCommunityLogo(id: UUID, logoPath: String?) async throws {
        struct Patch: Encodable { let logo_path: String? }
        try await client.from("communities").update(Patch(logo_path: logoPath)).eq("id", value: id).execute()
    }

    /// Logo in den öffentlichen Bucket; Pfad `<community_id>/<uuid>.jpg`.
    public func uploadCommunityLogo(_ data: Data, communityID: UUID) async throws -> String {
        let path = "\(communityID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("community-logos").upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    public func deleteCommunityLogo(path: String) async throws {
        _ = try await client.storage.from("community-logos").remove(paths: [path])
    }

    /// App-Admin: Anträge des Mandanten.
    public func pendingCommunities(tenantID: UUID) async throws -> [Community] {
        try await client.from("v_community_overview").select(Self.communityColumns)
            .eq("tenant_id", value: tenantID).eq("status", value: CommunityStatus.pending.rawValue).order("created_at").execute().value
    }

    public func setCommunityStatus(id: UUID, status: CommunityStatus) async throws {
        try await client.from("communities").update(["status": status.rawValue]).eq("id", value: id).execute()
    }

    // MARK: Mitgliedschaft

    public func myMemberships(userID: UUID) async throws -> [CommunityMember] {
        try await client.from("community_members").select("community_id, user_id, role, status, joined_at")
            .eq("user_id", value: userID).execute().value
    }

    public func members(communityID: UUID) async throws -> [CommunityMember] {
        try await client.from("community_members")
            .select("community_id, user_id, role, status, joined_at, profiles(user_id, display_name, avatar_url)")
            .eq("community_id", value: communityID).order("joined_at").execute().value
    }

    public func join(communityID: UUID, userID: UUID) async throws {
        struct Row: Encodable { let community_id: UUID; let user_id: UUID }
        try await client.from("community_members").insert(Row(community_id: communityID, user_id: userID)).execute()
    }

    public func leave(communityID: UUID, userID: UUID) async throws {
        try await client.from("community_members").delete().eq("community_id", value: communityID).eq("user_id", value: userID).execute()
    }

    public func setMember(communityID: UUID, userID: UUID, status: MemberStatus) async throws {
        try await client.from("community_members").update(["status": status.rawValue])
            .eq("community_id", value: communityID).eq("user_id", value: userID).execute()
    }

    public func setMember(communityID: UUID, userID: UUID, role: MemberRole) async throws {
        try await client.from("community_members").update(["role": role.rawValue])
            .eq("community_id", value: communityID).eq("user_id", value: userID).execute()
    }

    public func removeMember(communityID: UUID, userID: UUID) async throws {
        try await client.from("community_members").delete()
            .eq("community_id", value: communityID).eq("user_id", value: userID).execute()
    }

    // MARK: Termine

    private static let eventColumns = "id, community_id, title, description, starts_at, ends_at, location, image_path, visibility, published_at, cancelled_at, version, created_by, updated_at, communities(name, logo_path)"

    public func events(communityID: UUID, from: Date) async throws -> [CommunityEvent] {
        try await client.from("community_events").select(Self.eventColumns)
            .eq("community_id", value: communityID).gte("starts_at", value: from.ISO8601Format())
            .order("starts_at").execute().value
    }

    /// Termine aller eigenen Communities in einem Zeitraum — für den Kalender-Tab.
    public func events(communityIDs: [UUID], from: Date, to: Date) async throws -> [CommunityEvent] {
        guard !communityIDs.isEmpty else { return [] }
        return try await client.from("community_events").select(Self.eventColumns)
            .in("community_id", values: communityIDs.map(\.uuidString))
            .gte("starts_at", value: from.ISO8601Format()).lt("starts_at", value: to.ISO8601Format())
            .order("starts_at").execute().value
    }

    public func publicEvents(tenantID: UUID, from: Date, to: Date) async throws -> [PublicEvent] {
        try await client.from("v_public_events").select()
            .eq("tenant_id", value: tenantID)
            .gte("starts_at", value: from.ISO8601Format()).lt("starts_at", value: to.ISO8601Format())
            .order("starts_at").execute().value
    }

    public func createEvent(_ draft: CommunityEventDraft) async throws -> CommunityEvent {
        try await client.from("community_events").insert(draft).select(Self.eventColumns).single().execute().value
    }

    public func updateEvent(id: UUID, _ draft: CommunityEventDraft) async throws {
        try await client.from("community_events").update(draft).eq("id", value: id).execute()
    }

    public func cancelEvent(id: UUID) async throws {
        try await client.from("community_events").update(["cancelled_at": Date().ISO8601Format()]).eq("id", value: id).execute()
    }

    /// Lädt ein JPEG in den öffentlichen Bucket und liefert den Pfad für `image_path`.
    public func uploadEventPhoto(_ data: Data, communityID: UUID) async throws -> String {
        let path = "\(communityID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("event-photos").upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    public func deleteEventPhoto(path: String) async throws {
        _ = try await client.storage.from("event-photos").remove(paths: [path])
    }

    // MARK: Teilnahme

    public func participations(eventID: UUID) async throws -> [EventParticipation] {
        try await client.from("event_participations").select("event_id, user_id, status, profiles(user_id, display_name, avatar_url)")
            .eq("event_id", value: eventID).execute().value
    }

    public func myParticipations(userID: UUID) async throws -> [EventParticipation] {
        try await client.from("event_participations").select("event_id, user_id, status").eq("user_id", value: userID).execute().value
    }

    public func setParticipation(eventID: UUID, userID: UUID, status: ParticipationStatus?) async throws {
        if let status {
            struct Row: Encodable { let event_id: UUID; let user_id: UUID; let status: ParticipationStatus }
            try await client.from("event_participations").upsert(Row(event_id: eventID, user_id: userID, status: status)).execute()
        } else {
            try await client.from("event_participations").delete().eq("event_id", value: eventID).eq("user_id", value: userID).execute()
        }
    }

    // MARK: Kalender-Abo

    public func calendarToken(userID: UUID) async throws -> String {
        struct Row: Decodable { let token: String }
        let rows: [Row] = try await client.from("calendar_tokens").select("token").eq("user_id", value: userID).is("revoked_at", value: nil).execute().value
        if let token = rows.first?.token { return token }
        let created: Row = try await client.from("calendar_tokens").upsert(["user_id": userID.uuidString]).select("token").single().execute().value
        return created.token
    }

    public func rotateCalendarToken(userID: UUID) async throws -> String {
        try await client.from("calendar_tokens").delete().eq("user_id", value: userID).execute()
        return try await calendarToken(userID: userID)
    }

    // MARK: Konto

    public func deleteAccount() async throws {
        _ = try await client.functions.invoke("delete-account")
    }
}
