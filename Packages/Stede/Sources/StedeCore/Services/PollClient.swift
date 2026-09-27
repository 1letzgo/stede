import Foundation
import Supabase

/// Umfragen einer Gruppe — Tabellen `community_polls`, `community_poll_options`,
/// `community_poll_votes`. RLS: lesen und abstimmen nur aktive Mitglieder, anlegen,
/// beenden und löschen nur Admins/Leitung; abstimmen nur, solange die Umfrage offen ist.
public nonisolated struct PollClient: Sendable {
    private let client = Backend.client

    public init() {}

    private static let pollColumns = "id, community_id, question, description, kind, multiple, closes_at, closed_at, created_by, created_at, community_poll_options(id, label, starts_at, sort_order)"

    /// Neueste zuerst.
    public func polls(communityID: UUID) async throws -> [CommunityPoll] {
        try await client.from("community_polls").select(Self.pollColumns)
            .eq("community_id", value: communityID).order("created_at", ascending: false).limit(100).execute().value
    }

    public func votes(pollIDs: [UUID]) async throws -> [PollVote] {
        guard !pollIDs.isEmpty else { return [] }
        return try await client.from("community_poll_votes").select("poll_id, option_id, user_id, profiles(user_id, display_name, avatar_url)")
            .in("poll_id", values: pollIDs.map(\.uuidString)).execute().value
    }

    public func create(_ draft: PollDraft, communityID: UUID, userID: UUID) async throws {
        struct PollRow: Encodable {
            let community_id: UUID; let question: String; let description: String; let kind: PollKind
            let multiple: Bool; let closes_at: Date?; let created_by: UUID
        }
        struct Created: Decodable { let id: UUID }
        let poll: Created = try await client.from("community_polls")
            .insert(PollRow(community_id: communityID, question: draft.question, description: draft.description, kind: draft.kind,
                            multiple: draft.multiple, closes_at: draft.closesAt, created_by: userID))
            .select("id").single().execute().value
        struct OptionRow: Encodable { let poll_id: UUID; let label: String; let starts_at: Date?; let sort_order: Int }
        let rows = draft.options.enumerated().map { OptionRow(poll_id: poll.id, label: $1.label, starts_at: $1.startsAt, sort_order: $0) }
        do {
            try await client.from("community_poll_options").insert(rows).execute()
        } catch {
            // Ohne Antworten ist die Umfrage wertlos — wieder weg damit.
            try? await delete(pollID: poll.id)
            throw error
        }
    }

    public func vote(pollID: UUID, optionID: UUID, userID: UUID) async throws {
        struct Row: Encodable { let poll_id: UUID; let option_id: UUID; let user_id: UUID }
        try await client.from("community_poll_votes").insert(Row(poll_id: pollID, option_id: optionID, user_id: userID)).execute()
    }

    public func unvote(optionID: UUID, userID: UUID) async throws {
        try await client.from("community_poll_votes").delete()
            .eq("option_id", value: optionID).eq("user_id", value: userID).execute()
    }

    public func close(pollID: UUID) async throws {
        struct Patch: Encodable { let closed_at: Date }
        try await client.from("community_polls").update(Patch(closed_at: Date())).eq("id", value: pollID).execute()
    }

    public func delete(pollID: UUID) async throws {
        try await client.from("community_polls").delete().eq("id", value: pollID).execute()
    }
}
