import Foundation
import Supabase

/// Projekte und Aufgaben einer Gruppe — Tabellen `community_projects`, `community_tasks`,
/// `community_task_assignees`, `task_comments`. RLS: lesen aktive Mitglieder; Projekte
/// verwalten Admins/Leitung; Aufgaben legt jedes Mitglied an; ändern Admins, Ersteller und
/// Zuständige; zuweisen Admins und Ersteller, selbst übernehmen jedes Mitglied.
public nonisolated struct TaskClient: Sendable {
    private let client = Backend.client

    public init() {}

    private static let projectColumns = "id, community_id, title, description, created_by, created_at, archived_at"
    private static let taskColumns = "id, project_id, community_id, title, description, status, due_date, created_by, created_at, done_at, community_task_assignees(user_id, profiles(user_id, display_name, avatar_url))"

    // MARK: Projekte

    public func projects(communityID: UUID) async throws -> [CommunityProject] {
        try await client.from("community_projects").select(Self.projectColumns)
            .eq("community_id", value: communityID).order("created_at", ascending: false).execute().value
    }

    public func createProject(communityID: UUID, title: String, description: String, userID: UUID) async throws {
        struct Row: Encodable { let community_id: UUID; let title: String; let description: String; let created_by: UUID }
        try await client.from("community_projects").insert(Row(community_id: communityID, title: title, description: description, created_by: userID)).execute()
    }

    public func updateProject(id: UUID, title: String, description: String) async throws {
        struct Patch: Encodable { let title: String; let description: String }
        try await client.from("community_projects").update(Patch(title: title, description: description)).eq("id", value: id).execute()
    }

    public func setProjectArchived(id: UUID, archived: Bool) async throws {
        struct Patch: Encodable { let archived_at: Date? }
        try await client.from("community_projects").update(Patch(archived_at: archived ? Date() : nil)).eq("id", value: id).execute()
    }

    public func deleteProject(id: UUID) async throws {
        try await client.from("community_projects").delete().eq("id", value: id).execute()
    }

    // MARK: Aufgaben

    /// Alle Aufgaben der Gruppe (für Zähler auf den Projektkarten und die Projektansicht).
    public func tasks(communityID: UUID) async throws -> [CommunityTask] {
        try await client.from("community_tasks").select(Self.taskColumns)
            .eq("community_id", value: communityID).order("created_at").execute().value
    }

    /// Offene und laufende Aufgaben, für die der Nutzer zuständig ist — über alle Gruppen.
    public func myTasks(userID: UUID) async throws -> [AssignedTask] {
        try await client.from("community_tasks")
            .select(Self.taskColumns + ", community_projects(title, archived_at), mine:community_task_assignees!inner(user_id)")
            .eq("mine.user_id", value: userID)
            .neq("status", value: TaskStatus.done.rawValue)
            .order("due_date", ascending: true, nullsFirst: false)
            .order("created_at")
            .execute().value
    }

    public func createTask(projectID: UUID, communityID: UUID, draft: TaskDraft, userID: UUID) async throws {
        struct Row: Encodable {
            let project_id: UUID; let community_id: UUID; let title: String; let description: String
            let status: TaskStatus; let due_date: String?; let created_by: UUID
        }
        struct Created: Decodable { let id: UUID }
        let task: Created = try await client.from("community_tasks")
            .insert(Row(project_id: projectID, community_id: communityID, title: draft.title, description: draft.description,
                        status: draft.status, due_date: draft.due.map(IslandTime.isoDate), created_by: userID))
            .select("id").single().execute().value
        try await setAssignees(taskID: task.id, from: [], to: draft.assignees, by: userID)
    }

    public func updateTask(_ task: CommunityTask, draft: TaskDraft, userID: UUID, mayAssign: Bool) async throws {
        struct Patch: Encodable { let title: String; let description: String; let status: TaskStatus; let due_date: String? }
        try await client.from("community_tasks")
            .update(Patch(title: draft.title, description: draft.description, status: draft.status, due_date: draft.due.map(IslandTime.isoDate)))
            .eq("id", value: task.id).execute()
        if mayAssign {
            try await setAssignees(taskID: task.id, from: task.assignees.map(\.userId), to: draft.assignees, by: userID)
        }
    }

    public func setStatus(taskID: UUID, status: TaskStatus) async throws {
        struct Patch: Encodable { let status: TaskStatus }
        try await client.from("community_tasks").update(Patch(status: status)).eq("id", value: taskID).execute()
    }

    public func deleteTask(id: UUID) async throws {
        try await client.from("community_tasks").delete().eq("id", value: id).execute()
    }

    /// Selbst übernehmen.
    public func take(taskID: UUID, userID: UUID) async throws {
        try await setAssignees(taskID: taskID, from: [], to: [userID], by: userID)
    }

    /// Selbst abgeben.
    public func release(taskID: UUID, userID: UUID) async throws {
        try await client.from("community_task_assignees").delete().eq("task_id", value: taskID).eq("user_id", value: userID).execute()
    }

    private func setAssignees(taskID: UUID, from old: [UUID], to new: [UUID], by userID: UUID) async throws {
        let added = Set(new).subtracting(old)
        let removed = Set(old).subtracting(new)
        if !added.isEmpty {
            struct Row: Encodable { let task_id: UUID; let user_id: UUID; let assigned_by: UUID }
            try await client.from("community_task_assignees")
                .insert(added.map { Row(task_id: taskID, user_id: $0, assigned_by: userID) }).execute()
        }
        if !removed.isEmpty {
            try await client.from("community_task_assignees").delete()
                .eq("task_id", value: taskID).in("user_id", values: removed.map(\.uuidString)).execute()
        }
    }

    // MARK: Kommentare (`task_comments`) — gleiche Form wie `EventComment`, `event_id` ist hier die Aufgabe.

    public func comments(taskID: UUID) async throws -> [EventComment] {
        try await client.from("task_comments").select("id, event_id:task_id, user_id, body, created_at, profiles(user_id, display_name, avatar_url)")
            .eq("task_id", value: taskID).order("created_at").execute().value
    }

    public func addComment(taskID: UUID, userID: UUID, body: String) async throws {
        struct Row: Encodable { let task_id: UUID; let user_id: UUID; let body: String }
        try await client.from("task_comments").insert(Row(task_id: taskID, user_id: userID, body: body)).execute()
    }

    public func deleteComment(id: UUID) async throws {
        try await client.from("task_comments").delete().eq("id", value: id).execute()
    }

    public func commentCounts(taskIDs: [UUID]) async throws -> [UUID: Int] {
        guard !taskIDs.isEmpty else { return [:] }
        struct Row: Decodable { let task_id: UUID }
        let rows: [Row] = try await client.from("task_comments").select("task_id")
            .in("task_id", values: taskIDs.map(\.uuidString)).execute().value
        return Dictionary(grouping: rows, by: \.task_id).mapValues(\.count)
    }
}
