import Foundation

/// Projekt einer Gruppe (`community_projects`) — sammelt Aufgaben; nur Admins/Leitung legen an.
public nonisolated struct CommunityProject: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let communityId: UUID
    public var title: String
    public var description: String
    public let createdBy: UUID?
    public let createdAt: Date
    public var archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case communityId = "community_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case archivedAt = "archived_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        communityId = try c.decode(UUID.self, forKey: .communityId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}

public nonisolated enum TaskStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case open
    case inProgress = "in_progress"
    case done

    public var title: String {
        switch self {
        case .open: "Offen"
        case .inProgress: "In Arbeit"
        case .done: "Erledigt"
        }
    }
}

/// Aufgabe in einem Projekt (`community_tasks`) mit Zuständigen (`community_task_assignees`).
public nonisolated struct CommunityTask: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let projectId: UUID
    public let communityId: UUID
    public var title: String
    public var description: String
    public var status: TaskStatus
    /// Nur Datum (`YYYY-MM-DD`), ohne Uhrzeit.
    public var dueDate: String?
    public let createdBy: UUID?
    public let createdAt: Date
    public var doneAt: Date?
    public var assignees: [Assignee]

    public nonisolated struct Assignee: Codable, Hashable, Sendable {
        public let userId: UUID
        public var profile: Profile?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case profile = "profiles"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case projectId = "project_id"
        case communityId = "community_id"
        case dueDate = "due_date"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case doneAt = "done_at"
        case assignees = "community_task_assignees"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectId = try c.decode(UUID.self, forKey: .projectId)
        communityId = try c.decode(UUID.self, forKey: .communityId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .open
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        doneAt = try c.decodeIfPresent(Date.self, forKey: .doneAt)
        assignees = try c.decodeIfPresent([Assignee].self, forKey: .assignees) ?? []
    }

    /// Fälligkeitstag in Inselzeit.
    public var due: Date? { dueDate.flatMap(IslandTime.date(fromISO:)) }

    public func isAssigned(_ userID: UUID?) -> Bool {
        guard let userID else { return false }
        return assignees.contains { $0.userId == userID }
    }

    /// Überfällig: Fälligkeitstag vorbei und noch nicht erledigt.
    public func isOverdue(now: Date = Date()) -> Bool {
        guard status != .done, let due else { return false }
        return IslandTime.endOfDay(due) < now
    }
}

/// Eingabe für eine neue oder geänderte Aufgabe.
public nonisolated struct TaskDraft: Sendable {
    public var title: String
    public var description: String
    public var status: TaskStatus
    public var due: Date?
    public var assignees: [UUID]

    public init(title: String, description: String, status: TaskStatus, due: Date?, assignees: [UUID]) {
        self.title = title
        self.description = description
        self.status = status
        self.due = due
        self.assignees = assignees
    }
}

/// Eigene Aufgabe für „Meine Aufgaben“: die Aufgabe plus Titel ihres Projekts.
public nonisolated struct AssignedTask: Codable, Hashable, Sendable, Identifiable {
    public let task: CommunityTask
    public let projectTitle: String
    public let projectArchived: Bool

    public var id: UUID { task.id }

    private struct ProjectRef: Codable {
        let title: String
        let archivedAt: Date?
        enum CodingKeys: String, CodingKey { case title; case archivedAt = "archived_at" }
    }

    enum CodingKeys: String, CodingKey { case project = "community_projects" }

    public init(from decoder: Decoder) throws {
        task = try CommunityTask(from: decoder)
        let project = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(ProjectRef.self, forKey: .project)
        projectTitle = project?.title ?? ""
        projectArchived = project?.archivedAt != nil
    }

    /// Gleiche flache Form wie die Abfrage — für `CommunityCache`.
    public func encode(to encoder: Encoder) throws {
        try task.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ProjectRef(title: projectTitle, archivedAt: projectArchived ? Date(timeIntervalSince1970: 0) : nil), forKey: .project)
    }
}
