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
    public var avatarUrl: String?

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

    enum CodingKeys: String, CodingKey {
        case id, name, description, visibility, status
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

public nonisolated struct CommunityMember: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(communityId)|\(userId)" }
    public let communityId: UUID
    public let userId: UUID
    public var role: MemberRole
    public var status: MemberStatus
    public let joinedAt: Date?
    /// Per Join geladen: `profiles(display_name, avatar_url)`.
    public var profile: Profile?

    enum CodingKeys: String, CodingKey {
        case role, status
        case communityId = "community_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
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
    public var visibility: EventVisibility
    public var publishedAt: Date?
    public var cancelledAt: Date?
    public let version: Int
    public let createdBy: UUID?
    public let updatedAt: Date
    /// Per Join geladen: `communities(name)`.
    public var community: CommunityName?

    public nonisolated struct CommunityName: Codable, Hashable, Sendable {
        public let name: String
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, location, visibility, version
        case communityId = "community_id"
        case imagePath = "image_path"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case publishedAt = "published_at"
        case cancelledAt = "cancelled_at"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case community = "communities"
    }

    public var communityName: String { community?.name ?? "" }
    public var isPublic: Bool { visibility == .public && publishedAt != nil }
    public var imageURL: URL? { imagePath.map(Backend.eventPhotoURL) }
}

/// Öffentlicher Termin aus `v_public_events` — ohne Community-Interna.
public nonisolated struct PublicEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let tenantId: UUID
    public let communityName: String
    public let title: String
    public let description: String
    public let startsAt: Date
    public let endsAt: Date?
    public let location: String?
    public let imagePath: String?

    public var imageURL: URL? { imagePath.map(Backend.eventPhotoURL) }

    enum CodingKeys: String, CodingKey {
        case id, title, description, location
        case imagePath = "image_path"
        case tenantId = "tenant_id"
        case communityName = "community_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }
}

public nonisolated struct EventParticipation: Codable, Hashable, Sendable {
    public let eventId: UUID
    public let userId: UUID
    public var status: ParticipationStatus
    public var profile: Profile?

    enum CodingKeys: String, CodingKey {
        case status
        case eventId = "event_id"
        case userId = "user_id"
        case profile = "profiles"
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
    public var visibility: EventVisibility
    public var createdBy: UUID

    public init(communityId: UUID, title: String, description: String, startsAt: Date, endsAt: Date?, location: String?, imagePath: String? = nil, visibility: EventVisibility, createdBy: UUID) {
        self.communityId = communityId
        self.title = title
        self.description = description
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.location = location
        self.imagePath = imagePath
        self.visibility = visibility
        self.createdBy = createdBy
    }

    enum CodingKeys: String, CodingKey {
        case title, description, location, visibility
        case communityId = "community_id"
        case imagePath = "image_path"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case createdBy = "created_by"
    }
}
