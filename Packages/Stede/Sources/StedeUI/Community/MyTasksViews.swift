import StedeCore
import SwiftUI

/// „Meine Aufgaben“ im Gruppen-Reiter: alle offenen und laufenden Aufgaben des Nutzers
/// über alle Gruppen, nach Gruppe sortiert.
@Observable
final class MyTasksModel {
    var tasks: [AssignedTask]?
    var commentCounts: [UUID: Int] = [:]
    var lastError: String?
    private let client = TaskClient()

    /// Zuerst der letzte Stand von der Platte, dann das Netz (`CommunityCache`).
    func load(userID: UUID?) async {
        guard let userID else { tasks = nil; return }
        if tasks == nil { tasks = CommunityCache.load([AssignedTask].self, "my-tasks", userID: userID) }
        do {
            let list = try await client.myTasks(userID: userID).filter { !$0.projectArchived }
            tasks = list
            CommunityCache.save(list, "my-tasks", userID: userID)
            commentCounts = (try? await client.commentCounts(taskIDs: list.map(\.id))) ?? commentCounts
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Führt eine Änderung aus und lädt danach neu; Fehler landen in `lastError`.
    func run(userID: UUID?, _ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            lastError = error.localizedDescription
        }
        await load(userID: userID)
    }
}

/// Ziel „Gruppe im Reiter Aufgaben öffnen“ — getrennt vom normalen Gruppen-Link.
struct CommunityTasksDestination: Hashable {
    let community: Community
}

/// Ziel „Meine Aufgaben“ im Gruppen-Reiter.
struct MyTasksDestination: Hashable {}

/// Eigene Kategorie „Meine Aufgaben“ ganz oben im Gruppen-Tab, nur mit offenen Aufgaben: eine Karte mit der Anzahl offener Aufgaben, öffnet `MyTasksView`.
struct MyTasksLink: View {
    let model: MyTasksModel
    /// Eigene Gruppen mit eingeschalteten Aufgaben.
    let communities: [Community]

    var body: some View {
        // Nur wenn dir etwas zugewiesen ist — sonst bleibt der Gruppen-Tab aufgeräumt.
        let own = (model.tasks ?? []).filter { task in communities.contains { $0.id == task.task.communityId } }
        if !own.isEmpty {
            let groups = Set(own.map(\.task.communityId)).count
            StedeSectionHeader(title: "Meine Aufgaben", symbol: "checklist")
            NavigationLink(value: MyTasksDestination()) {
                HStack(spacing: 12) {
                    StedeIconChip(symbol: "checklist", color: StedeTheme.sunAmber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aufgaben").font(.headline)
                        Text("\(own.count) offen · \(groups == 1 ? "1 Gruppe" : "\(groups) Gruppen")")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(StedeTheme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
            }
            .buttonStyle(StedeCardButtonStyle()).foregroundStyle(.primary)
        }
    }
}

/// Alle eigenen offenen Aufgaben, nach Gruppen sortiert: je Gruppe ein Kopf (öffnet deren Aufgaben), darunter die Aufgaben.
struct MyTasksView: View {
    let model: MyTasksModel
    /// Eigene Gruppen mit eingeschalteten Aufgaben, in der Reihenfolge der Gruppenliste.
    let communities: [Community]
    @Environment(AuthStore.self) private var auth
    @State private var commentingTask: CommunityTask?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                if groups.isEmpty, model.tasks != nil {
                    InfoCard { Text("Gerade ist dir keine offene Aufgabe zugewiesen.").foregroundStyle(.secondary) }
                }
                ForEach(groups, id: \.community.id) { group in
                    NavigationLink(value: CommunityTasksDestination(community: group.community)) {
                        GroupRow(community: group.community, count: group.tasks.count)
                    }
                    .buttonStyle(StedeCardButtonStyle()).foregroundStyle(.primary)
                    ForEach(group.tasks) { item in
                        card(item, in: group.community)
                    }
                }
                if let error = model.lastError { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
            }
            .padding()
        }
        .background(StedeTheme.sand)
        .navigationTitle("Meine Aufgaben")
        .stedeBar()
        .refreshable { await model.load(userID: auth.userID) }
        .task { await model.load(userID: auth.userID) }
        .sheet(item: $commentingTask, onDismiss: { Task { await model.load(userID: auth.userID) } }) { task in
            CommentsSheet(title: task.title, target: .task(task.id), canModerate: Self.permissions(for: task.communityId, auth: auth).isAdmin)
        }
    }

    /// Gruppen mit eigenen Aufgaben; Aufgaben ohne sichtbare Gruppe (andere Gemeinde) fallen weg.
    private var groups: [(community: Community, tasks: [AssignedTask])] {
        let tasks = model.tasks ?? []
        return communities.compactMap { community in
            let own = tasks.filter { $0.task.communityId == community.id }
            return own.isEmpty ? nil : (community, own)
        }
    }

    static func permissions(for communityID: UUID, auth: AuthStore) -> TaskPermissions {
        let membership = auth.membership(for: communityID)
        let isAdmin = membership?.status == .active && (membership?.role == .owner || membership?.role == .admin)
        return TaskPermissions(userID: auth.userID, isAdmin: isAdmin)
    }

    private func card(_ item: AssignedTask, in community: Community) -> some View {
        let task = item.task
        let me = auth.userID
        return TaskCard(
            task: task, permissions: Self.permissions(for: community.id, auth: auth), commentCount: model.commentCounts[task.id] ?? 0,
            onStatus: { status in Task { await model.run(userID: me) { try await TaskClient().setStatus(taskID: task.id, status: status) } } },
            onTake: {},
            onRelease: { Task { if let me { await model.run(userID: me) { try await TaskClient().release(taskID: task.id, userID: me) } } } },
            onEdit: nil,
            onDelete: { Task { await model.run(userID: me) { try await TaskClient().deleteTask(id: task.id) } } },
            onComments: { commentingTask = task },
            context: item.projectTitle
        )
    }
}

/// Kopfzeile einer Gruppe in „Meine Aufgaben“: Logo, Name, Anzahl, Pfeil.
private struct GroupRow: View {
    let community: Community
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            CommunityAvatar(logoURL: community.logoURL, name: community.name, side: 28)
            Text(community.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Text(count == 1 ? "1 Aufgabe" : "\(count) Aufgaben").font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .stedeRowCard()
    }
}
