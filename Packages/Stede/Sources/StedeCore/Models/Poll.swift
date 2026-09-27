import Foundation

/// Art einer Umfrage: freie Antworten oder Terminfindung (Antworten sind Zeitpunkte).
public nonisolated enum PollKind: String, Codable, Hashable, Sendable, CaseIterable {
    case text
    case date
}

/// Umfrage einer Gruppe (`community_polls`) — nur für aktive Mitglieder sichtbar.
public nonisolated struct CommunityPoll: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let communityId: UUID
    public var question: String
    public var description: String
    public var kind: PollKind
    /// Mehrere Antworten erlaubt; sonst ersetzt eine neue Stimme die alte (Trigger in der DB).
    public var multiple: Bool
    /// Automatisches Ende, nil = offen bis zum manuellen Beenden.
    public var closesAt: Date?
    /// Von Hand beendet.
    public var closedAt: Date?
    public let createdBy: UUID?
    public let createdAt: Date
    /// Per Embed geladen, nach `sort_order`.
    public var options: [PollOption]

    enum CodingKeys: String, CodingKey {
        case id, question, description, kind, multiple
        case communityId = "community_id"
        case closesAt = "closes_at"
        case closedAt = "closed_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case options = "community_poll_options"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        communityId = try c.decode(UUID.self, forKey: .communityId)
        question = try c.decode(String.self, forKey: .question)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        kind = try c.decodeIfPresent(PollKind.self, forKey: .kind) ?? .text
        multiple = try c.decodeIfPresent(Bool.self, forKey: .multiple) ?? false
        closesAt = try c.decodeIfPresent(Date.self, forKey: .closesAt)
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        options = (try c.decodeIfPresent([PollOption].self, forKey: .options) ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Offen, solange nicht beendet und das Enddatum nicht erreicht ist.
    public func isOpen(now: Date = Date()) -> Bool {
        closedAt == nil && (closesAt.map { $0 > now } ?? true)
    }
}

/// Eine Antwortmöglichkeit; bei Terminfindung trägt sie den Zeitpunkt.
public nonisolated struct PollOption: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var label: String
    public var startsAt: Date?
    public var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, label
        case startsAt = "starts_at"
        case sortOrder = "sort_order"
    }
}

/// Eine Stimme mit Namen (Umfragen sind immer offen: alle Mitglieder sehen, wer was gewählt hat).
public nonisolated struct PollVote: Codable, Hashable, Sendable {
    public let pollId: UUID
    public let optionId: UUID
    public let userId: UUID
    public var profile: Profile?

    enum CodingKeys: String, CodingKey {
        case pollId = "poll_id"
        case optionId = "option_id"
        case userId = "user_id"
        case profile = "profiles"
    }
}

/// Eingabe für eine neue Umfrage.
public nonisolated struct PollDraft: Sendable {
    public var question: String
    public var description: String
    public var kind: PollKind
    public var multiple: Bool
    public var closesAt: Date?
    /// Text (Antworten) oder Zeitpunkt (Terminfindung) je Möglichkeit, in Reihenfolge.
    public var options: [(label: String, startsAt: Date?)]

    public init(question: String, description: String, kind: PollKind, multiple: Bool, closesAt: Date?, options: [(label: String, startsAt: Date?)]) {
        self.question = question
        self.description = description
        self.kind = kind
        self.multiple = multiple
        self.closesAt = closesAt
        self.options = options
    }
}
