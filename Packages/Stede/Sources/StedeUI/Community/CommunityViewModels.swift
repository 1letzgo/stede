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
    /// Archiv: erst beim Öffnen des Reiters geladen, seitenweise (20) beim Scrollen; nil = nicht geladen.
    var pastEvents: [CommunityEvent]?
    var loadingPast = false
    var hasMorePast = true
    private static let pastPageSize = 20
    var myParticipations: [UUID: MyParticipation] = [:]
    var helperCounts: [UUID: Int] = [:]
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
                    myParticipations = Dictionary(uniqueKeysWithValues: mine.map { ($0.eventId, MyParticipation(status: $0.status, helping: $0.helping)) })
                }
                helperCounts = try await client.helperCounts(eventIDs: events.filter { $0.helpersNeeded > 0 }.map(\.id))
                if pastEvents != nil { await loadPastEvents() }
            } else {
                members = []
                events = []
            }
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Erste Seite des Archivs (oder neu laden, z. B. nach Bearbeiten).
    func loadPastEvents() async {
        await loadPast(offset: 0)
    }

    /// Nächste Seite, wenn das Ende der Liste sichtbar wird.
    func loadMorePastEvents() async {
        guard hasMorePast, !loadingPast, let count = pastEvents?.count else { return }
        await loadPast(offset: count)
    }

    private func loadPast(offset: Int) async {
        loadingPast = true
        defer { loadingPast = false }
        do {
            let page = try await client.pastEvents(communityID: community.id, before: IslandTime.startOfDay(Date()),
                                                   offset: offset, limit: Self.pastPageSize)
            let counts = try await client.helperCounts(eventIDs: page.filter { $0.helpersNeeded > 0 }.map(\.id))
            helperCounts.merge(counts) { _, new in new }
            hasMorePast = page.count == Self.pastPageSize
            pastEvents = offset == 0 ? page : (pastEvents ?? []) + page
        } catch {
            lastError = error.localizedDescription
        }
    }

    var pendingMembers: [CommunityMember] { members.filter { $0.status == .pending } }
    var activeMembers: [CommunityMember] { members.filter { $0.status == .active } }

    func join(userID: UUID, message: String? = nil) async throws {
        try await client.join(communityID: community.id, userID: userID, message: message)
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
            if pastEvents != nil { await loadPastEvents() }
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
            if pastEvents != nil { await loadPastEvents() }
        } catch { lastError = error.localizedDescription }
    }

    func setParticipation(event: CommunityEvent, userID: UUID, status: ParticipationStatus?, helping: Bool = false) async {
        do {
            try await client.setParticipation(eventID: event.id, userID: userID, status: status, helping: helping)
            if let status { myParticipations[event.id] = MyParticipation(status: status, helping: helping && status != .declined) } else { myParticipations[event.id] = nil }
            if event.helpersNeeded > 0 { helperCounts = try await client.helperCounts(eventIDs: [event.id]).merging(helperCounts) { new, _ in new } }
        } catch { lastError = error.localizedDescription }
    }

    func updateSettings(name: String, description: String, visibility: CommunityVisibility, joinPolicy: CommunityJoinPolicy, logoPath: String?) async -> Bool {
        do {
            try await client.updateCommunity(id: community.id, name: name, description: description, visibility: visibility, joinPolicy: joinPolicy, countywide: community.isCountywide, logoPath: logoPath)
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
    var myParticipations: [UUID: MyParticipation] = [:]
    var helperCounts: [UUID: Int] = [:]
    private let client = CommunityClient()

    /// Lädt bei jedem Aufruf neu — Termine entstehen auch in anderen Tabs.
    func load(from start: Date, to end: Date, tenantID: UUID?, memberCommunityIDs: [UUID], userID: UUID?) async {
        guard let tenantID else { return }
        do {
            async let publicTask = client.publicEvents(tenantID: tenantID, from: start, to: end)
            async let memberTask = client.events(communityIDs: memberCommunityIDs, from: start, to: end)
            publicEvents = try await publicTask
            memberEvents = try await memberTask
            if let userID {
                let mine = try await client.myParticipations(userID: userID)
                myParticipations = Dictionary(uniqueKeysWithValues: mine.map { ($0.eventId, MyParticipation(status: $0.status, helping: $0.helping)) })
            } else {
                myParticipations = [:]
            }
            let helperIDs = memberEvents.filter { $0.helpersNeeded > 0 }.map(\.id) + publicEvents.filter { $0.helpersNeeded > 0 }.map(\.id)
            helperCounts = try await client.helperCounts(eventIDs: helperIDs)
        } catch {
            // Community-Termine sind Beiwerk im Kalender: Fehler stören die Stadt-Termine nicht.
        }
    }

    func setParticipation(eventID: UUID, userID: UUID, status: ParticipationStatus?, helping: Bool = false) async {
        do {
            try await client.setParticipation(eventID: eventID, userID: userID, status: status, helping: helping)
            myParticipations[eventID] = status.map { MyParticipation(status: $0, helping: helping && $0 != .declined) }
            helperCounts = try await client.helperCounts(eventIDs: [eventID]).merging(helperCounts) { new, _ in new }
        } catch {
            // Fehler zeigt sich daran, dass die Pille nicht umspringt.
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
