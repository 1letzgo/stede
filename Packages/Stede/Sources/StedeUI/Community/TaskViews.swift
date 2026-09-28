import StedeCore
import SwiftUI

/// Projekte und Aufgaben einer Gruppe; lädt beim Öffnen des Reiters „Aufgaben“.
@Observable
final class TasksModel {
    var projects: [CommunityProject]?
    var tasks: [CommunityTask] = []
    var commentCounts: [UUID: Int] = [:]
    var lastError: String?
    private let client = TaskClient()

    func load(communityID: UUID) async {
        do {
            async let projectsTask = client.projects(communityID: communityID)
            async let tasksTask = client.tasks(communityID: communityID)
            let (list, all) = try await (projectsTask, tasksTask)
            projects = list
            tasks = all
            commentCounts = (try? await client.commentCounts(taskIDs: all.map(\.id))) ?? commentCounts
            lastError = nil
        } catch {
            if projects == nil { projects = [] }
            lastError = error.localizedDescription
        }
    }

    func tasks(in project: CommunityProject) -> [CommunityTask] { tasks.filter { $0.projectId == project.id } }

    /// Führt eine Änderung aus und lädt danach neu; Fehler landen in `lastError`.
    func run(_ communityID: UUID, _ action: () async throws -> Void) async -> Bool {
        do {
            try await action()
            await load(communityID: communityID)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

/// Wer was darf — spiegelt die RLS-Regeln, damit die Oberfläche nur Machbares anbietet.
struct TaskPermissions {
    let userID: UUID?
    let isAdmin: Bool

    func canEdit(_ task: CommunityTask) -> Bool { isAdmin || (userID != nil && task.createdBy == userID) }
    func canChangeStatus(_ task: CommunityTask) -> Bool { canEdit(task) || task.isAssigned(userID) }
}

enum TaskFormat {
    static func due(_ date: Date) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: IslandTime.germanLocale, calendar: IslandTime.calendar, timeZone: IslandTime.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated)
        return "bis \(date.formatted(style))"
    }

    static func color(_ status: TaskStatus) -> Color {
        switch status {
        case .open: StedeTheme.sunAmber
        case .inProgress: StedeTheme.seaTeal
        case .done: StedeTheme.duneGreen
        }
    }

    static func symbol(_ status: TaskStatus) -> String {
        switch status {
        case .open: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }
}

// MARK: Projektliste (Reiter)

/// Karte eines Projekts: Titel, Fortschritt, offene und eigene Aufgaben.
struct ProjectCard: View {
    let project: CommunityProject
    let tasks: [CommunityTask]
    let userID: UUID?

    private var done: Int { tasks.filter { $0.status == .done }.count }
    private var open: Int { tasks.filter { $0.status == .open }.count }
    private var working: Int { tasks.filter { $0.status == .inProgress }.count }
    private var mine: Int { tasks.filter { $0.status != .done && $0.isAssigned(userID) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: "checklist", color: StedeTheme.sunAmber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title).font(.headline).multilineTextAlignment(.leading)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            if !project.description.isEmpty {
                Text(project.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            if !tasks.isEmpty {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(StedeTheme.duneGreen.opacity(0.15))
                        Capsule().fill(StedeTheme.duneGreen).frame(width: geo.size.width * Double(done) / Double(tasks.count))
                    }
                }
                .frame(height: 6)
            }
            if mine > 0 {
                StedeTagPill(text: mine == 1 ? "1 Aufgabe für dich" : "\(mine) Aufgaben für dich", color: StedeTheme.seaTeal)
            }
        }
        .padding(StedeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard()
        .opacity(project.archivedAt == nil ? 1 : 0.7)
    }

    private var summary: String {
        if tasks.isEmpty { return project.archivedAt == nil ? "Noch keine Aufgaben" : "Archiviert" }
        var parts = ["\(done) von \(tasks.count) erledigt"]
        if working > 0 { parts.append("\(working) in Arbeit") }
        if open > 0 { parts.append("\(open) offen") }
        if project.archivedAt != nil { parts.append("archiviert") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Projekt

/// Aufgaben eines Projekts nach Status; jedes Mitglied legt Aufgaben an und übernimmt sie.
struct ProjectDetailView: View {
    let project: CommunityProject
    let model: TasksModel
    let members: [CommunityMember]
    let permissions: TaskPermissions
    @Environment(\.dismiss) private var dismiss
    @State private var onlyMine = false
    @State private var showsNewTask = false
    @State private var editingTask: CommunityTask?
    @State private var commentingTask: CommunityTask?
    @State private var editingProject = false
    @State private var confirmDelete = false

    private var current: CommunityProject { model.projects?.first { $0.id == project.id } ?? project }
    private var tasks: [CommunityTask] {
        let all = model.tasks(in: project)
        return onlyMine ? all.filter { $0.isAssigned(permissions.userID) } : all
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                if !current.description.isEmpty {
                    Text(current.description).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
                HStack(spacing: StedeTheme.SelectionRow.spacing) {
                    ForEach([false, true], id: \.self) { mine in
                        Button { onlyMine = mine } label: {
                            Text(mine ? "Meine" : "Alle").frame(maxWidth: .infinity).stedeSelectionChip(isSelected: onlyMine == mine)
                        }
                        .buttonStyle(StedeCardButtonStyle())
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                if tasks.isEmpty {
                    InfoCard {
                        Text(onlyMine ? "Dir ist hier keine Aufgabe zugewiesen." : "Noch keine Aufgaben. Leg die erste mit + an.")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    let group = tasks.filter { $0.status == status }
                    if !group.isEmpty {
                        StedeSectionHeader(title: "\(status.title) \(group.count)", symbol: TaskFormat.symbol(status))
                        ForEach(group) { task in
                            TaskCard(
                                task: task, permissions: permissions, commentCount: model.commentCounts[task.id] ?? 0,
                                onStatus: { status in Task { _ = await model.run(project.communityId) { try await TaskClient().setStatus(taskID: task.id, status: status) } } },
                                onTake: { Task { if let me = permissions.userID { _ = await model.run(project.communityId) { try await TaskClient().take(taskID: task.id, userID: me) } } } },
                                onRelease: { Task { if let me = permissions.userID { _ = await model.run(project.communityId) { try await TaskClient().release(taskID: task.id, userID: me) } } } },
                                onEdit: { editingTask = task },
                                onDelete: { Task { _ = await model.run(project.communityId) { try await TaskClient().deleteTask(id: task.id) } } },
                                onComments: { commentingTask = task }
                            )
                        }
                    }
                }
                if let error = model.lastError { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
            }
            .padding()
        }
        .background(StedeTheme.sand)
        .navigationTitle(current.title)
        .stedeBar()
        .refreshable { await model.load(communityID: project.communityId) }
        .toolbar {
            if permissions.isAdmin {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Projekt bearbeiten", systemImage: "pencil") { editingProject = true }
                        Button(current.archivedAt == nil ? "Archivieren" : "Wieder aktivieren", systemImage: "archivebox") {
                            Task { _ = await model.run(project.communityId) { try await TaskClient().setProjectArchived(id: project.id, archived: current.archivedAt == nil) } }
                        }
                        Button("Projekt löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.white) }
                    .tint(.white)
                    .accessibilityLabel("Projekt verwalten")
                }
            }
            if current.archivedAt == nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsNewTask = true } label: { Image(systemName: "plus").foregroundStyle(.white) }
                        .tint(.white)
                        .accessibilityLabel("Aufgabe anlegen")
                }
            }
        }
        .confirmationDialog("Projekt löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task { if await model.run(project.communityId, { try await TaskClient().deleteProject(id: project.id) }) { dismiss() } }
            }
        } message: {
            Text("Alle Aufgaben und Kommentare des Projekts werden entfernt.")
        }
        .sheet(isPresented: $showsNewTask) {
            TaskEditorView(existing: nil, members: members, mayAssign: true) { draft in
                guard let me = permissions.userID else { return false }
                return await model.run(project.communityId) {
                    try await TaskClient().createTask(projectID: project.id, communityID: project.communityId, draft: draft, userID: me)
                }
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorView(existing: task, members: members, mayAssign: permissions.canEdit(task)) { draft in
                guard let me = permissions.userID else { return false }
                return await model.run(project.communityId) {
                    try await TaskClient().updateTask(task, draft: draft, userID: me, mayAssign: permissions.canEdit(task))
                }
            }
        }
        .sheet(item: $commentingTask, onDismiss: { Task { await model.load(communityID: project.communityId) } }) { task in
            CommentsSheet(title: task.title, target: .task(task.id), canModerate: permissions.isAdmin)
        }
        .sheet(isPresented: $editingProject) {
            ProjectEditorView(existing: current) { title, description in
                await model.run(project.communityId) { try await TaskClient().updateProject(id: project.id, title: title, description: description) }
            }
        }
    }
}

/// Eine Aufgabe: Status, Titel, Fälligkeit, Zuständige; übernehmen, Status ändern, kommentieren.
struct TaskCard: View {
    let task: CommunityTask
    let permissions: TaskPermissions
    let commentCount: Int
    let onStatus: (TaskStatus) -> Void
    let onTake: () -> Void
    let onRelease: () -> Void
    /// Ohne Editor (etwa in „Meine Aufgaben“, wo die Mitgliederliste fehlt) entfällt „Bearbeiten“.
    let onEdit: (() -> Void)?
    let onDelete: () -> Void
    let onComments: () -> Void
    /// Projekttitel über der Aufgabe, wenn sie außerhalb ihres Projekts steht.
    var context: String? = nil
    @State private var confirmDelete = false

    private var mine: Bool { task.isAssigned(permissions.userID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                statusControl
                VStack(alignment: .leading, spacing: 4) {
                    if let context, !context.isEmpty {
                        Text(context).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(task.title).font(.headline).strikethrough(task.status == .done)
                        .foregroundStyle(task.status == .done ? .secondary : .primary)
                    HStack(spacing: 6) {
                        StedeTagPill(text: task.status.title, color: TaskFormat.color(task.status))
                        if let due = task.due {
                            StedeTagPill(text: TaskFormat.due(due), color: task.isOverdue() ? StedeTheme.harborRed : StedeTheme.mudflat)
                        }
                    }
                }
                Spacer(minLength: 0)
                menu
            }
            if !task.description.isEmpty {
                Text(task.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(4)
            }
            assigneesRow
            HStack(spacing: 8) {
                if !mine, task.status != .done, permissions.userID != nil {
                    Button(action: onTake) {
                        StedeColorChip(title: "Übernehmen", symbol: "hand.raised.fill", color: StedeTheme.seaTeal, prominent: true)
                    }
                    .buttonStyle(StedeCardButtonStyle())
                }
                Spacer(minLength: 0)
                CommentsButton(count: commentCount, tint: StedeTheme.sunAmber, action: onComments)
            }
        }
        .padding(StedeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard()
        .confirmationDialog("Aufgabe löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: onDelete)
        }
    }

    /// Kreis links: Tippen hakt ab (oder öffnet wieder) — nur für Zuständige, Ersteller und Admins.
    @ViewBuilder private var statusControl: some View {
        let symbol = Image(systemName: TaskFormat.symbol(task.status)).font(.title2).foregroundStyle(TaskFormat.color(task.status))
        if permissions.canChangeStatus(task) {
            Button { onStatus(task.status == .done ? .open : .done) } label: { symbol }
                .buttonStyle(StedeCardButtonStyle())
                .accessibilityLabel(task.status == .done ? "Wieder öffnen" : "Als erledigt markieren")
        } else {
            symbol.accessibilityHidden(true)
        }
    }

    @ViewBuilder private var menu: some View {
        if permissions.canChangeStatus(task) || mine {
            Menu {
                if permissions.canChangeStatus(task) {
                    ForEach(TaskStatus.allCases.filter { $0 != task.status }, id: \.self) { status in
                        Button(status.title, systemImage: TaskFormat.symbol(status)) { onStatus(status) }
                    }
                }
                if mine { Button("Abgeben", systemImage: "hand.raised.slash", action: onRelease) }
                if permissions.canEdit(task) {
                    if let onEdit { Button("Bearbeiten", systemImage: "pencil", action: onEdit) }
                    Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(StedeTheme.ink)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .accessibilityLabel("Aufgabe verwalten")
        }
    }

    @ViewBuilder private var assigneesRow: some View {
        if task.assignees.isEmpty {
            Label("Noch niemand zuständig", systemImage: "person.crop.circle.badge.questionmark")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                HStack(spacing: -8) {
                    ForEach(task.assignees.prefix(4), id: \.userId) { person in
                        PersonAvatar(url: person.profile?.avatarURL, name: person.profile?.displayName ?? "?", side: 26)
                            .overlay(Circle().stroke(StedeTheme.surface, lineWidth: 2))
                    }
                }
                Text(task.assignees.compactMap { $0.profile?.displayName }.sorted().joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

// MARK: Editoren

struct ProjectEditorView: View {
    let existing: CommunityProject?
    let onSave: (String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Projekt") {
                    TextField("Titel, z. B. Sommerfest", text: $title)
                    TextField("Beschreibung (optional)", text: $description, axis: .vertical).lineLimit(2 ... 6)
                }
            }
            .navigationTitle(existing == nil ? "Neues Projekt" : "Projekt bearbeiten")
            .stedeSheetForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        Task {
                            saving = true
                            if await onSave(title.trimmingCharacters(in: .whitespaces), description.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
                            saving = false
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                if let existing { title = existing.title; description = existing.description }
            }
        }
    }
}

struct TaskEditorView: View {
    let existing: CommunityTask?
    let members: [CommunityMember]
    /// Zuständige wählen dürfen Admins, Ersteller und wer eine neue Aufgabe anlegt.
    let mayAssign: Bool
    let onSave: (TaskDraft) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var status: TaskStatus = .open
    @State private var hasDue = false
    @State private var due = IslandTime.day(Date(), adding: 7)
    @State private var assignees: Set<UUID> = []
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Aufgabe") {
                    TextField("Titel", text: $title, axis: .vertical).lineLimit(1 ... 3)
                    TextField("Beschreibung (optional)", text: $description, axis: .vertical).lineLimit(2 ... 6)
                }
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Fällig bis", isOn: $hasDue.animation())
                    if hasDue { DatePicker("Datum", selection: $due, displayedComponents: .date) }
                }
                if mayAssign {
                    Section {
                        ForEach(members.sorted { ($0.profile?.displayName ?? "") < ($1.profile?.displayName ?? "") }) { member in
                            Button {
                                if assignees.contains(member.userId) { assignees.remove(member.userId) } else { assignees.insert(member.userId) }
                            } label: {
                                HStack(spacing: 10) {
                                    PersonAvatar(url: member.profile?.avatarURL, name: member.profile?.displayName ?? "Mitglied", side: 30)
                                    Text(member.profile?.displayName ?? "Mitglied").foregroundStyle(.primary)
                                    Spacer()
                                    if assignees.contains(member.userId) {
                                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(StedeTheme.ink)
                                    }
                                }
                            }
                            .accessibilityAddTraits(assignees.contains(member.userId) ? .isSelected : [])
                        }
                    } header: {
                        Text("Zuständig")
                    } footer: {
                        Text("Mitglieder können offene Aufgaben auch selbst übernehmen.")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Neue Aufgabe" : "Aufgabe bearbeiten")
            .stedeSheetForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                if let existing {
                    title = existing.title; description = existing.description; status = existing.status
                    if let date = existing.due { hasDue = true; due = date }
                    assignees = Set(existing.assignees.map(\.userId))
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let draft = TaskDraft(title: title.trimmingCharacters(in: .whitespaces), description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                              status: status, due: hasDue ? due : nil,
                              assignees: mayAssign ? Array(assignees) : (existing?.assignees.map(\.userId) ?? []))
        if await onSave(draft) { dismiss() }
    }
}
