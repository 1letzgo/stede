import Foundation
import StedeCore

/// Liste der Communities des Mandanten.
@Observable
final class CommunityListModel {
    var communities: [Community] = []
    var state: LoadState = .idle
    private let client = CommunityClient()

    func load(tenantID: UUID?) async {
        guard let tenantID else { return }
        if communities.isEmpty { state = .loading }
        do {
            communities = try await client.communities(tenantID: tenantID).filter { $0.status != .rejected && $0.status != .archived }
            state = communities.isEmpty ? .empty : .loaded
        } catch {
            if communities.isEmpty { state = .failed(error.localizedDescription) }
        }
    }
}

/// Eine Community: Mitglieder, Termine, Teilnahmen.
@Observable
final class CommunityDetailModel {
    var community: Community
    var members: [CommunityMember] = []
    var events: [CommunityEvent] = []
    var myParticipations: [UUID: ParticipationStatus] = [:]
    var state: LoadState = .idle
    var lastError: String?
    private let client = CommunityClient()

    init(community: Community) {
        self.community = community
    }

    func load(userID: UUID?, isMember: Bool) async {
        state = .loading
        do {
            community = try await client.community(id: community.id)
            if isMember {
                async let membersTask = client.members(communityID: community.id)
                async let eventsTask = client.events(communityID: community.id, from: IslandTime.startOfDay(Date()))
                members = try await membersTask
                events = try await eventsTask
                if let userID {
                    let mine = try await client.myParticipations(userID: userID)
                    myParticipations = Dictionary(uniqueKeysWithValues: mine.map { ($0.eventId, $0.status) })
                }
            } else {
                members = []
                events = []
            }
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var pendingMembers: [CommunityMember] { members.filter { $0.status == .pending } }
    var activeMembers: [CommunityMember] { members.filter { $0.status == .active } }

    func join(userID: UUID) async throws {
        try await client.join(communityID: community.id, userID: userID)
    }

    func leave(userID: UUID) async throws {
        try await client.leave(communityID: community.id, userID: userID)
    }

    func setMember(_ member: CommunityMember, status: MemberStatus) async {
        do {
            if status == .banned {
                try await client.removeMember(communityID: community.id, userID: member.userId)
            } else {
                try await client.setMember(communityID: community.id, userID: member.userId, status: status)
            }
            members = try await client.members(communityID: community.id)
        } catch { lastError = error.localizedDescription }
    }

    func setMember(_ member: CommunityMember, role: MemberRole) async {
        do {
            try await client.setMember(communityID: community.id, userID: member.userId, role: role)
            members = try await client.members(communityID: community.id)
        } catch { lastError = error.localizedDescription }
    }

    func save(_ draft: CommunityEventDraft, editing id: UUID?) async -> Bool {
        do {
            if let id { try await client.updateEvent(id: id, draft) } else { _ = try await client.createEvent(draft) }
            events = try await client.events(communityID: community.id, from: IslandTime.startOfDay(Date()))
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func cancel(event: CommunityEvent) async {
        do {
            try await client.cancelEvent(id: event.id)
            events = try await client.events(communityID: community.id, from: IslandTime.startOfDay(Date()))
        } catch { lastError = error.localizedDescription }
    }

    func setParticipation(event: CommunityEvent, userID: UUID, status: ParticipationStatus?) async {
        do {
            try await client.setParticipation(eventID: event.id, userID: userID, status: status)
            if let status { myParticipations[event.id] = status } else { myParticipations[event.id] = nil }
        } catch { lastError = error.localizedDescription }
    }

    func updateSettings(name: String, description: String, visibility: CommunityVisibility, joinPolicy: CommunityJoinPolicy) async -> Bool {
        do {
            try await client.updateCommunity(id: community.id, name: name, description: description, visibility: visibility, joinPolicy: joinPolicy)
            community = try await client.community(id: community.id)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

/// Community-Termine für den Kalender-Tab: öffentliche des Mandanten plus die der eigenen Communities.
@Observable
final class CommunityCalendarModel {
    var publicEvents: [PublicEvent] = []
    var memberEvents: [CommunityEvent] = []
    private let client = CommunityClient()
    private var loadedKey: String?

    func load(day: Date, tenantID: UUID?, memberCommunityIDs: [UUID], force: Bool = false) async {
        guard let tenantID else { return }
        let key = "\(IslandTime.isoDate(day))|\(memberCommunityIDs.map(\.uuidString).sorted().joined())"
        if !force, loadedKey == key { return }
        let start = IslandTime.startOfDay(day)
        let end = IslandTime.endOfDay(day)
        do {
            async let publicTask = client.publicEvents(tenantID: tenantID, from: start, to: end)
            async let memberTask = client.events(communityIDs: memberCommunityIDs, from: start, to: end)
            publicEvents = try await publicTask
            memberEvents = try await memberTask
            loadedKey = key
        } catch {
            // Community-Termine sind Beiwerk im Kalender: Fehler stören die Stadt-Termine nicht.
        }
    }
}

/// Tab „Admin“: Anträge des Mandanten und Mitgliedsanfragen der eigenen Communities.
@Observable
final class AdminModel {
    var pendingCommunities: [Community] = []
    var requests: [(community: Community, member: CommunityMember)] = []
    var state: LoadState = .idle
    var lastError: String?
    private let client = CommunityClient()

    func load(tenantID: UUID?, isTenantAdmin: Bool, adminCommunityIDs: [UUID]) async {
        state = .loading
        do {
            if isTenantAdmin, let tenantID {
                pendingCommunities = try await client.pendingCommunities(tenantID: tenantID)
            } else {
                pendingCommunities = []
            }
            var collected: [(Community, CommunityMember)] = []
            for id in adminCommunityIDs {
                let community = try await client.community(id: id)
                let pending = try await client.members(communityID: id).filter { $0.status == .pending }
                collected += pending.map { (community, $0) }
            }
            requests = collected
            state = (pendingCommunities.isEmpty && requests.isEmpty) ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func decide(community: Community, approve: Bool) async {
        do {
            try await client.setCommunityStatus(id: community.id, status: approve ? .approved : .rejected)
            pendingCommunities.removeAll { $0.id == community.id }
        } catch { lastError = error.localizedDescription }
    }

    func decide(request: (community: Community, member: CommunityMember), accept: Bool) async {
        do {
            if accept {
                try await client.setMember(communityID: request.community.id, userID: request.member.userId, status: .active)
            } else {
                try await client.removeMember(communityID: request.community.id, userID: request.member.userId)
            }
            requests.removeAll { $0.member.id == request.member.id }
        } catch { lastError = error.localizedDescription }
    }
}
