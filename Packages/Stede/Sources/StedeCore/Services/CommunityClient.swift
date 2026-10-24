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

    /// Profilbild hochladen; der Ordner ist die eigene User-ID (RLS).
    public func uploadAvatar(_ data: Data, userID: UUID) async throws -> String {
        let path = "\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("avatars").upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    public func setAvatar(userID: UUID, path: String?) async throws {
        try await client.from("profiles").update(["avatar_url": path]).eq("user_id", value: userID).execute()
    }

    public func deleteAvatar(path: String) async throws {
        _ = try await client.storage.from("avatars").remove(paths: [path])
    }

    // MARK: Communities

    private static let communityColumns = "id, tenant_id, name, description, visibility, join_policy, status, invite_code, logo_path, created_by, created_at, member_count, countywide, polls_enabled, tasks_enabled, can_transfer_events"

    /// Gruppen der eigenen Gemeinde plus die kreisweiten aus dem ganzen Ammerland.
    static func ownOrCountywide(_ tenantID: UUID) -> String {
        "tenant_id.eq.\(tenantID.uuidString.lowercased()),and(countywide.is.true,region.eq.\(AppBrand.current.region))"
    }

    /// Termine: Gruppen nur ihrer Gemeinde · kreisweite ohne Auswahl · kreisweite, deren Termin
    /// diese Gemeinde gewählt hat (`target_tenants` — auch die Heimatgemeinde muss dann gewählt sein).
    static func ownOrTargeted(_ tenantID: UUID) -> String {
        let id = tenantID.uuidString.lowercased()
        return "and(countywide.is.false,tenant_id.eq.\(id)),and(countywide.is.true,region.eq.\(AppBrand.current.region),target_tenants.is.null),and(countywide.is.true,target_tenants.cs.{\(id)})"
    }

    /// Wie `ownOrTargeted`, aber für mehrere Gemeinden auf einmal.
    static func anyTargeted(_ tenantIDs: [UUID]) -> String {
        let ids = tenantIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
        return "and(countywide.is.false,tenant_id.in.(\(ids))),and(countywide.is.true,region.eq.\(AppBrand.current.region),target_tenants.is.null),and(countywide.is.true,target_tenants.ov.{\(ids)})"
    }

    /// Alle sichtbaren Communities des Mandanten (gelistete plus eigene) und die kreisweiten.
    public func communities(tenantID: UUID) async throws -> [Community] {
        try await client.from("v_community_overview").select(Self.communityColumns)
            .or(Self.ownOrCountywide(tenantID)).order("name").execute().value
    }

    public func community(id: UUID) async throws -> Community {
        try await client.from("v_community_overview").select(Self.communityColumns).eq("id", value: id).single().execute().value
    }

    public func communityByInvite(code: String) async throws -> Community? {
        let rows: [Community] = try await client.from("v_community_overview").select(Self.communityColumns)
            .eq("invite_code", value: code).limit(1).execute().value
        return rows.first
    }

    public func createCommunity(tenantID: UUID, name: String, description: String, visibility: CommunityVisibility, joinPolicy: CommunityJoinPolicy, countywide: Bool, userID: UUID) async throws -> Community {
        struct Draft: Encodable {
            let tenant_id: UUID; let name: String; let description: String
            let visibility: CommunityVisibility; let join_policy: CommunityJoinPolicy; let countywide: Bool; let created_by: UUID
        }
        let created: Community = try await client.from("communities")
            .insert(Draft(tenant_id: tenantID, name: name, description: description, visibility: visibility, join_policy: joinPolicy, countywide: countywide, created_by: userID))
            .select("id, tenant_id, name, description, visibility, join_policy, status, invite_code, logo_path, created_by, created_at, countywide").single().execute().value
        return created
    }

    public func updateCommunity(id: UUID, name: String, description: String, visibility: CommunityVisibility, joinPolicy: CommunityJoinPolicy, countywide: Bool, logoPath: String?) async throws {
        struct Patch: Encodable { let name: String; let description: String; let visibility: CommunityVisibility; let join_policy: CommunityJoinPolicy; let countywide: Bool; let logo_path: String? }
        try await client.from("communities").update(Patch(name: name, description: description, visibility: visibility, join_policy: joinPolicy, countywide: countywide, logo_path: logoPath)).eq("id", value: id).execute()
    }

    /// Umfragen und Aufgaben der Gruppe ein- oder ausschalten.
    public func setFeatures(id: UUID, polls: Bool, tasks: Bool) async throws {
        struct Patch: Encodable { let polls_enabled: Bool; let tasks_enabled: Bool }
        try await client.from("communities").update(Patch(polls_enabled: polls, tasks_enabled: tasks)).eq("id", value: id).execute()
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
    /// Offene Beitrittsanfragen in den Gruppen, die der Nutzer verwaltet.
    public func pendingMemberCount(communityIDs: [UUID]) async throws -> Int {
        guard !communityIDs.isEmpty else { return 0 }
        struct Row: Decodable { let user_id: UUID }
        let rows: [Row] = try await client.from("community_members").select("user_id")
            .in("community_id", values: communityIDs.map(\.uuidString)).eq("status", value: "pending").execute().value
        return rows.count
    }

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
            .select("community_id, user_id, role, status, joined_at, join_message, profiles(user_id, display_name, avatar_url)")
            .eq("community_id", value: communityID).order("joined_at").execute().value
    }

    /// Beitritt bzw. Antrag; `message` ist die optionale Kurzvorstellung für die Admins.
    public func join(communityID: UUID, userID: UUID, message: String? = nil) async throws {
        struct Row: Encodable { let community_id: UUID; let user_id: UUID; let join_message: String? }
        let text = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.from("community_members")
            .insert(Row(community_id: communityID, user_id: userID, join_message: text?.isEmpty == false ? String(text!.prefix(500)) : nil))
            .execute()
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

    private static let eventColumns = "id, community_id, title, description, starts_at, ends_at, location, image_path, visibility, published_at, cancelled_at, version, created_by, updated_at, helpers_needed, comments_enabled, target_tenants, external_key, rsvp_enabled, all_day, organizer, category, source_url, source_name, image_credit, price, registration, sold_out, organizer_id, communities(name, logo_path)"

    public func events(communityID: UUID, from: Date) async throws -> [CommunityEvent] {
        try await client.from("community_events").select(Self.eventColumns)
            .eq("community_id", value: communityID).gte("starts_at", value: from.ISO8601Format())
            .order("starts_at").execute().value
    }

    /// Vergangene Termine einer Community, neueste zuerst.
    public func pastEvents(communityID: UUID, before: Date, offset: Int = 0, limit: Int = 20) async throws -> [CommunityEvent] {
        try await client.from("community_events").select(Self.eventColumns)
            .eq("community_id", value: communityID).lt("starts_at", value: before.ISO8601Format())
            .order("starts_at", ascending: false).range(from: offset, to: offset + limit - 1).execute().value
    }

    /// Termine aller eigenen Communities in einem Zeitraum — für den Kalender-Tab.
    public func events(communityIDs: [UUID], from: Date, to: Date) async throws -> [CommunityEvent] {
        guard !communityIDs.isEmpty else { return [] }
        return try await client.from("community_events").select(Self.eventColumns)
            .in("community_id", values: communityIDs.map(\.uuidString))
            .gte("starts_at", value: from.ISO8601Format()).lt("starts_at", value: to.ISO8601Format())
            .order("starts_at").execute().value
    }

    /// Seitenweise zu 1000 — mit den übernommenen Gemeinde-Terminen kommen über Monate mehr zusammen,
    /// als PostgREST in einer Antwort liefert.
    /// `extraTenants`: weitere Gemeinden aus „Termine der Region“ — deren Termine kommen dazu wie die der
    /// eigenen Gemeinde (eigene Gruppen-Termine, kreisweite ohne Auswahl, kreisweite mit einer der Gemeinden).
    public func publicEvents(tenantID: UUID, from: Date, to: Date, extraTenants: [UUID] = []) async throws -> [PublicEvent] {
        let page = 1000
        var all: [PublicEvent] = []
        while true {
            let base = client.from("v_public_events").select()
            let scoped = extraTenants.isEmpty ? base.or(Self.ownOrTargeted(tenantID)) : base.or(Self.anyTargeted([tenantID] + extraTenants))
            let rows: [PublicEvent] = try await scoped
                .gte("starts_at", value: from.ISO8601Format()).lt("starts_at", value: to.ISO8601Format())
                .order("starts_at").order("id").range(from: all.count, to: all.count + page - 1).execute().value
            all += rows
            if rows.count < page { return all }
        }
    }

    public func createEvent(_ draft: CommunityEventDraft) async throws -> CommunityEvent {
        try await client.from("community_events").insert(draft).select(Self.eventColumns).single().execute().value
    }

    public func updateEvent(id: UUID, _ draft: CommunityEventDraft) async throws {
        try await client.from("community_events").update(draft).eq("id", value: id).execute()
    }

    /// Kommentare eines internen Termins ein- oder ausschalten (Schnellmenü der Karte).
    public func setEventComments(id: UUID, enabled: Bool) async throws {
        struct Patch: Encodable { let comments_enabled: Bool }
        try await client.from("community_events").update(Patch(comments_enabled: enabled)).eq("id", value: id).execute()
    }

    /// Termin der Veranstaltungs-Gruppe an eine andere Gruppe übertragen; `series` nimmt alle künftigen Termine
    /// gleichen Titels mit und leitet neue Importe dieser Reihe gleich dorthin. Liefert die Zahl der Termine.
    @discardableResult
    public func transferEvents(eventID: UUID, to target: UUID, series: Bool) async throws -> Int {
        struct Params: Encodable { let p_event: UUID; let p_target: UUID; let p_series: Bool }
        return try await client.rpc("transfer_events", params: Params(p_event: eventID, p_target: target, p_series: series)).execute().value
    }

    /// Verknüpft den Veranstalter des Termins mit der Zielgruppe: alle künftigen Termine dieses Veranstalters
    /// wandern dorthin, neue Importe landen direkt dort. Liefert die Zahl der verschobenen Termine.
    public func transferOrganizer(eventID: UUID, to target: UUID) async throws -> Int {
        struct Params: Encodable { let p_event: UUID; let p_target: UUID }
        return try await client.rpc("transfer_organizer", params: Params(p_event: eventID, p_target: target)).execute().value
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
        guard !CommunityHeaderImage.isDefault(path: path) else { return }
        _ = try await client.storage.from("event-photos").remove(paths: [path])
    }

    // MARK: Standardbilder

    public func headerImages(communityID: UUID) async throws -> [CommunityHeaderImage] {
        try await client.from("community_header_images").select("id, community_id, path, label, sort_order")
            .eq("community_id", value: communityID).order("sort_order").order("created_at").execute().value
    }

    public func addHeaderImage(_ data: Data, label: String, communityID: UUID, userID: UUID, sortOrder: Int) async throws {
        let path = "\(communityID.uuidString.lowercased())/defaults/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from("event-photos").upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        struct Row: Encodable { let community_id: UUID; let path: String; let label: String; let sort_order: Int; let created_by: UUID }
        try await client.from("community_header_images")
            .insert(Row(community_id: communityID, path: path, label: label, sort_order: sortOrder, created_by: userID)).execute()
    }

    /// Entfernt Eintrag und Datei. Termine, die das Bild nutzen, verlieren ihr Kopfbild.
    public func deleteHeaderImage(_ image: CommunityHeaderImage) async throws {
        try await client.from("community_header_images").delete().eq("id", value: image.id).execute()
        try? await client.from("community_events").update(["image_path": String?.none])
            .eq("community_id", value: image.communityId).eq("image_path", value: image.path).execute()
        _ = try? await client.storage.from("event-photos").remove(paths: [image.path])
    }

    // MARK: Kommentare

    public func comments(eventID: UUID) async throws -> [EventComment] {
        try await client.from("event_comments").select("id, event_id, user_id, body, created_at, profiles(user_id, display_name, avatar_url)")
            .eq("event_id", value: eventID).order("created_at").execute().value
    }

    public func addComment(eventID: UUID, userID: UUID, body: String) async throws {
        struct Row: Encodable { let event_id: UUID; let user_id: UUID; let body: String }
        try await client.from("event_comments").insert(Row(event_id: eventID, user_id: userID, body: body)).execute()
    }

    /// Anzahl Kommentare je Termin — für den Knopf unter der Karte.
    public func commentCounts(eventIDs: [UUID]) async throws -> [UUID: Int] {
        guard !eventIDs.isEmpty else { return [:] }
        struct Row: Decodable { let event_id: UUID }
        let rows: [Row] = try await client.from("event_comments").select("event_id")
            .in("event_id", values: eventIDs.map(\.uuidString)).execute().value
        return Dictionary(grouping: rows, by: \.event_id).mapValues(\.count)
    }

    public func deleteComment(id: UUID) async throws {
        try await client.from("event_comments").delete().eq("id", value: id).execute()
    }

    // MARK: Teilnahme

    public func participations(eventID: UUID) async throws -> [EventParticipation] {
        try await client.from("event_participations").select("event_id, user_id, status, helping, profiles(user_id, display_name, avatar_url)")
            .eq("event_id", value: eventID).execute().value
    }

    public func myParticipations(userID: UUID) async throws -> [EventParticipation] {
        try await client.from("event_participations").select("event_id, user_id, status, helping").eq("user_id", value: userID).execute().value
    }

    /// Zusage setzen (nil löscht die Zeile); `helping` nur mit Zusage oder Vielleicht.
    public func setParticipation(eventID: UUID, userID: UUID, status: ParticipationStatus?, helping: Bool = false) async throws {
        if let status {
            struct Row: Encodable { let event_id: UUID; let user_id: UUID; let status: ParticipationStatus; let helping: Bool }
            try await client.from("event_participations").upsert(Row(event_id: eventID, user_id: userID, status: status, helping: helping && status != .declined)).execute()
        } else {
            try await client.from("event_participations").delete().eq("event_id", value: eventID).eq("user_id", value: userID).execute()
        }
    }

    /// Helferzahl je Termin, auch für Termine fremder Communities.
    public func helperCounts(eventIDs: [UUID]) async throws -> [UUID: Int] {
        guard !eventIDs.isEmpty else { return [:] }
        struct Row: Decodable { let event_id: UUID; let helpers: Int }
        struct Params: Encodable { let event_ids: [UUID] }
        let rows: [Row] = try await client.rpc("event_helper_counts", params: Params(event_ids: eventIDs)).execute().value
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.event_id, $0.helpers) })
    }

    // MARK: Kalender-Abo

    public func calendarToken(userID: UUID) async throws -> String {
        struct Row: Decodable { let token: String }
        let rows: [Row] = try await client.from("calendar_tokens").select("token").eq("user_id", value: userID).is("revoked_at", value: nil).execute().value
        if let token = rows.first?.token { return token }
        let created: Row = try await client.from("calendar_tokens").upsert(["user_id": userID.uuidString]).select("token").single().execute().value
        return created.token
    }

    // MARK: Konto

    public func deleteAccount() async throws {
        _ = try await client.functions.invoke("delete-account")
    }
}
