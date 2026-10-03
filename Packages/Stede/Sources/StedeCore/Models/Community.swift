import Foundation

/// Datensätze des Community-Teils, 1:1 zu den Tabellen in Supabase (snake_case).

public nonisolated struct Tenant: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let slug: String
    public let name: String
    public let municipality: String
}

public nonisolated struct Profile: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { userId }
    public let userId: UUID
    public var displayName: String
    /// Pfad im Bucket `avatars` (`<user_id>/<uuid>.jpg`) oder eine volle URL.
    public var avatarUrl: String?

    /// Profilbild zum Anzeigen, nil ohne Bild.
    public var avatarURL: URL? {
        guard let avatarUrl, !avatarUrl.isEmpty else { return nil }
        return avatarUrl.hasPrefix("http") ? URL(string: avatarUrl) : Backend.avatarURL(path: avatarUrl)
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

public nonisolated enum CommunityVisibility: String, Codable, Sendable, CaseIterable { case listed, hidden }
public nonisolated enum CommunityJoinPolicy: String, Codable, Sendable, CaseIterable { case open, approval }
public nonisolated enum CommunityStatus: String, Codable, Sendable { case pending, approved, rejected, archived }
public nonisolated enum MemberRole: String, Codable, Sendable { case owner, admin, member }
public nonisolated enum MemberStatus: String, Codable, Sendable { case pending, active, banned }
public nonisolated enum EventVisibility: String, Codable, Sendable { case members, `public` }
public nonisolated enum ParticipationStatus: String, Codable, Sendable { case going, maybe, declined }

public nonisolated struct Community: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let tenantId: UUID
    public var name: String
    public var description: String
    public var visibility: CommunityVisibility
    public var joinPolicy: CommunityJoinPolicy
    public var status: CommunityStatus
    public var inviteCode: String?
    public var logoPath: String?
    public let createdBy: UUID
    public let createdAt: Date
    public var memberCount: Int?
    /// Kreisweit: auch in den anderen Ammerland-Gemeinden gelistet (fehlt in manchen Abfragen).
    public var countywide: Bool?

    public var isCountywide: Bool { countywide ?? false }
    /// Gruppen-Funktionen, in den Einstellungen schaltbar (fehlen in manchen Abfragen).
    public var pollsEnabled: Bool?
    public var tasksEnabled: Bool?
    /// Sonderfunktion der Veranstaltungs-Gruppe: Termine an andere Gruppen übertragen (nur im Backend freischaltbar).
    public var canTransferEvents: Bool?
    public var hasPolls: Bool { pollsEnabled ?? true }
    public var hasTasks: Bool { tasksEnabled ?? false }

    enum CodingKeys: String, CodingKey {
        case id, name, description, visibility, status, countywide
        case pollsEnabled = "polls_enabled"
        case tasksEnabled = "tasks_enabled"
        case canTransferEvents = "can_transfer_events"
        case tenantId = "tenant_id"
        case joinPolicy = "join_policy"
        case inviteCode = "invite_code"
        case logoPath = "logo_path"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case memberCount = "member_count"
    }

    public var logoURL: URL? { logoPath.map(Backend.communityLogoURL) }
}

/// Standardbild einer Community — als Termin-Kopfbild wählbar statt eines eigenen Fotos.
/// Die Datei liegt in `event-photos/<community>/defaults/`; Termine verweisen nur darauf.
public nonisolated struct CommunityHeaderImage: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let communityId: UUID
    public let path: String
    public var label: String
    public var sortOrder: Int

    public var url: URL { Backend.eventPhotoURL(path: path) }

    /// Pfade von Standardbildern dürfen beim Foto-Wechsel eines Termins nicht gelöscht werden.
    public static func isDefault(path: String) -> Bool { path.contains("/defaults/") }

    enum CodingKeys: String, CodingKey {
        case id, path, label
        case communityId = "community_id"
        case sortOrder = "sort_order"
    }
}

public nonisolated struct CommunityMember: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(communityId)|\(userId)" }
    public let communityId: UUID
    public let userId: UUID
    public var role: MemberRole
    public var status: MemberStatus
    public let joinedAt: Date?
    /// Kurze Vorstellung aus dem Beitrittsantrag; nach der Freischaltung leer.
    public var joinMessage: String?
    /// Per Join geladen: `profiles(display_name, avatar_url)`.
    public var profile: Profile?

    enum CodingKeys: String, CodingKey {
        case role, status
        case communityId = "community_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case joinMessage = "join_message"
        case profile = "profiles"
    }
}

public nonisolated struct CommunityEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let communityId: UUID
    public var title: String
    public var description: String
    public var startsAt: Date
    public var endsAt: Date?
    public var location: String?
    public var imagePath: String?
    /// 0 = keine Helfer gesucht.
    public var helpersNeeded: Int
    /// Kommentare der Mitglieder — vom Ersteller eingeschaltet, auch bei öffentlichen Terminen nur für Mitglieder.
    public var commentsEnabled: Bool
    public var visibility: EventVisibility
    /// Nur bei kreisweiten Gruppen: nil = kreisweit, sonst nur diese Gemeinden (plus Heimatgemeinde).
    public var targetTenants: [UUID]?
    public var publishedAt: Date?
    public var cancelledAt: Date?
    public let version: Int
    public let createdBy: UUID?
    public let updatedAt: Date
    /// Per Join geladen: `communities(name)`.
    public var community: CommunityName?
    /// Aus einem Gemeinde-Kalender übernommen (`<gemeinde>:<id>:<tag>`); nil = in der App angelegt.
    public var externalKey: String?
    /// Teilnahme abfragen (Zusage, Vielleicht, Absage, Helfer); übernommene Termine standardmäßig ohne.
    public var rsvpEnabled: Bool
    public var allDay: Bool
    public var organizer: String?
    public var category: String?
    public var sourceURL: String?
    public var sourceName: String?
    public var imageCredit: String?
    public var price: String?
    public var registration: String?
    public var soldOut: Bool
    /// Veranstalter eines übernommenen Termins (Tabelle `organizers`).
    public var organizerID: UUID?

    public nonisolated struct CommunityName: Codable, Hashable, Sendable {
        public let name: String
        public let logoPath: String?

        public init(name: String, logoPath: String?) {
            self.name = name
            self.logoPath = logoPath
        }

        enum CodingKeys: String, CodingKey {
            case name
            case logoPath = "logo_path"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, location, visibility, version
        case communityId = "community_id"
        case imagePath = "image_path"
        case helpersNeeded = "helpers_needed"
        case commentsEnabled = "comments_enabled"
        case targetTenants = "target_tenants"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case publishedAt = "published_at"
        case cancelledAt = "cancelled_at"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case community = "communities"
        case externalKey = "external_key"
        case rsvpEnabled = "rsvp_enabled"
        case allDay = "all_day"
        case organizer, category, price, registration
        case sourceURL = "source_url"
        case sourceName = "source_name"
        case imageCredit = "image_credit"
        case soldOut = "sold_out"
        case organizerID = "organizer_id"
    }

    public var origin: EventOrigin {
        EventOrigin(allDay: allDay, organizer: organizer, category: category, sourceURL: sourceURL, sourceName: sourceName,
                    imageCredit: imageCredit, price: price, registration: registration, soldOut: soldOut)
    }

    public var communityName: String { community?.name ?? "" }
    public var communityLogoURL: URL? { community?.logoPath.map(Backend.communityLogoURL) }
    public var isPublic: Bool { visibility == .public && publishedAt != nil }
    public var imageURL: URL? { imagePath.map(Backend.eventPhotoURL) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        communityId = try c.decode(UUID.self, forKey: .communityId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        startsAt = try c.decode(Date.self, forKey: .startsAt)
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        imagePath = try c.decodeIfPresent(String.self, forKey: .imagePath)
        helpersNeeded = try c.decodeIfPresent(Int.self, forKey: .helpersNeeded) ?? 0
        // Ältere Zwischenspeicher kennen das Feld noch nicht.
        commentsEnabled = try c.decodeIfPresent(Bool.self, forKey: .commentsEnabled) ?? false
        visibility = try c.decode(EventVisibility.self, forKey: .visibility)
        targetTenants = try c.decodeIfPresent([UUID].self, forKey: .targetTenants)
        publishedAt = try c.decodeIfPresent(Date.self, forKey: .publishedAt)
        cancelledAt = try c.decodeIfPresent(Date.self, forKey: .cancelledAt)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        community = try c.decodeIfPresent(CommunityName.self, forKey: .community)
        externalKey = try c.decodeIfPresent(String.self, forKey: .externalKey)
        rsvpEnabled = try c.decodeIfPresent(Bool.self, forKey: .rsvpEnabled) ?? true
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        organizer = try c.decodeIfPresent(String.self, forKey: .organizer)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName)
        imageCredit = try c.decodeIfPresent(String.self, forKey: .imageCredit)
        price = try c.decodeIfPresent(String.self, forKey: .price)
        registration = try c.decodeIfPresent(String.self, forKey: .registration)
        soldOut = try c.decodeIfPresent(Bool.self, forKey: .soldOut) ?? false
        organizerID = try c.decodeIfPresent(UUID.self, forKey: .organizerID)
    }
}

/// Herkunft eines Termins aus einem Gemeinde-Kalender (Import in die Gruppe „stede Veranstaltungen“):
/// ganztägig, Veranstalter, Rubrik, Quelle mit Link und Foto-Credit. Bei Terminen aus der App leer.
public nonisolated struct EventOrigin: Hashable, Sendable {
    public var allDay = false
    public var organizer: String?
    public var category: String?
    public var sourceURL: String?
    public var sourceName: String?
    public var imageCredit: String?
    public var price: String?
    public var registration: String?
    public var soldOut = false

    public init(allDay: Bool = false, organizer: String? = nil, category: String? = nil, sourceURL: String? = nil, sourceName: String? = nil,
                imageCredit: String? = nil, price: String? = nil, registration: String? = nil, soldOut: Bool = false) {
        self.allDay = allDay; self.organizer = organizer; self.category = category; self.sourceURL = sourceURL
        self.sourceName = sourceName; self.imageCredit = imageCredit; self.price = price; self.registration = registration
        self.soldOut = soldOut
    }

    /// Aus einem Gemeinde-Kalender übernommen.
    public var isImported: Bool { sourceName != nil }
    public var link: URL? { sourceURL.flatMap { URL(string: $0) } }
}

/// Öffentlicher Termin aus `v_public_events` — ohne Community-Interna.
public nonisolated struct PublicEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let tenantId: UUID
    public let communityName: String
    public let communityLogoPath: String?
    public let title: String
    public let description: String
    public let startsAt: Date
    public let endsAt: Date?
    public let location: String?
    public let imagePath: String?
    public let helpersNeeded: Int
    public let allDay: Bool?
    public let organizer: String?
    public let category: String?
    public let sourceURL: String?
    public let sourceName: String?
    public let imageCredit: String?
    public let price: String?
    public let registration: String?
    public let rsvpEnabled: Bool?
    public let soldOut: Bool?

    public var origin: EventOrigin {
        EventOrigin(allDay: allDay ?? false, organizer: organizer, category: category, sourceURL: sourceURL, sourceName: sourceName,
                    imageCredit: imageCredit, price: price, registration: registration, soldOut: soldOut ?? false)
    }

    public var imageURL: URL? { imagePath.map(Backend.eventPhotoURL) }
    public var communityLogoURL: URL? { communityLogoPath.map(Backend.communityLogoURL) }

    enum CodingKeys: String, CodingKey {
        case id, title, description, location
        case imagePath = "image_path"
        case helpersNeeded = "helpers_needed"
        case tenantId = "tenant_id"
        case communityName = "community_name"
        case communityLogoPath = "community_logo_path"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
        case organizer, category, price, registration
        case sourceURL = "source_url"
        case sourceName = "source_name"
        case imageCredit = "image_credit"
        case rsvpEnabled = "rsvp_enabled"
        case soldOut = "sold_out"
    }
}

public nonisolated struct EventParticipation: Codable, Hashable, Sendable {
    public let eventId: UUID
    public let userId: UUID
    public var status: ParticipationStatus
    public var helping: Bool
    public var profile: Profile?

    enum CodingKeys: String, CodingKey {
        case status, helping
        case eventId = "event_id"
        case userId = "user_id"
        case profile = "profiles"
    }
}

/// Eigener Stand zu einem Termin: Zusage plus Helfer-Flag.
public nonisolated struct MyParticipation: Hashable, Sendable {
    public var status: ParticipationStatus
    public var helping: Bool

    public init(status: ParticipationStatus, helping: Bool) {
        self.status = status
        self.helping = helping
    }
}

/// Neue oder geänderte Termine, wie die App sie sendet.
public nonisolated struct CommunityEventDraft: Codable, Sendable {
    public var communityId: UUID
    public var title: String
    public var description: String
    public var startsAt: Date
    public var endsAt: Date?
    public var location: String?
    public var imagePath: String?
    public var helpersNeeded: Int
    public var commentsEnabled: Bool
    /// Teilnahme abfragen; aus = keine Zusagen und keine Helfer.
    public var rsvpEnabled: Bool
    public var visibility: EventVisibility
    /// nil = kreisweit (oder Gruppe nicht kreisweit), sonst nur diese Gemeinden.
    public var targetTenants: [UUID]?
    public var createdBy: UUID

    public init(communityId: UUID, title: String, description: String, startsAt: Date, endsAt: Date?, location: String?, imagePath: String? = nil, helpersNeeded: Int = 0, commentsEnabled: Bool = false, rsvpEnabled: Bool = true, visibility: EventVisibility, targetTenants: [UUID]? = nil, createdBy: UUID) {
        self.communityId = communityId
        self.title = title
        self.description = description
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.location = location
        self.imagePath = imagePath
        self.helpersNeeded = rsvpEnabled ? helpersNeeded : 0
        self.commentsEnabled = commentsEnabled
        self.rsvpEnabled = rsvpEnabled
        self.visibility = visibility
        self.targetTenants = visibility == .public ? targetTenants : nil
        self.createdBy = createdBy
    }

    enum CodingKeys: String, CodingKey {
        case title, description, location, visibility
        case communityId = "community_id"
        case imagePath = "image_path"
        case helpersNeeded = "helpers_needed"
        case commentsEnabled = "comments_enabled"
        case rsvpEnabled = "rsvp_enabled"
        case targetTenants = "target_tenants"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case createdBy = "created_by"
    }

    /// `target_tenants` immer mitschicken — auch als null, sonst bliebe beim Bearbeiten
    /// eine alte Auswahl stehen, wenn der Termin wieder kreisweit wird.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(communityId, forKey: .communityId)
        try c.encode(title, forKey: .title)
        try c.encode(description, forKey: .description)
        try c.encode(startsAt, forKey: .startsAt)
        try c.encode(endsAt, forKey: .endsAt)
        try c.encode(location, forKey: .location)
        try c.encode(imagePath, forKey: .imagePath)
        try c.encode(helpersNeeded, forKey: .helpersNeeded)
        try c.encode(commentsEnabled, forKey: .commentsEnabled)
        try c.encode(rsvpEnabled, forKey: .rsvpEnabled)
        try c.encode(visibility, forKey: .visibility)
        try c.encode(targetTenants, forKey: .targetTenants)
        try c.encode(createdBy, forKey: .createdBy)
    }
}

/// Kommentar zu einem internen Gruppen-Termin (Tabelle `event_comments`).
public nonisolated struct EventComment: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let eventId: UUID
    public let userId: UUID
    public let body: String
    public let createdAt: Date
    public var profile: Profile?

    enum CodingKeys: String, CodingKey {
        case id, body
        case eventId = "event_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case profile = "profiles"
    }
}
