import StedeCore
import SwiftUI

/// Umfragen einer Gruppe samt Stimmen; lädt beim Öffnen des Reiters „Umfragen“.
@Observable
final class PollsModel {
    var polls: [CommunityPoll]?
    var votes: [UUID: [PollVote]] = [:]
    var commentCounts: [UUID: Int] = [:]
    var lastError: String?
    private let client = PollClient()

    func load(communityID: UUID) async {
        do {
            let list = try await client.polls(communityID: communityID)
            let all = try await client.votes(pollIDs: list.map(\.id))
            votes = Dictionary(grouping: all, by: \.pollId)
            commentCounts = (try? await client.commentCounts(pollIDs: list.filter(\.commentsEnabled).map(\.id))) ?? commentCounts
            polls = list
            lastError = nil
        } catch {
            if polls == nil { polls = [] }
            lastError = error.localizedDescription
        }
    }

    /// Antwort an- oder abwählen; bei Einfachauswahl ersetzt der Server die alte Stimme.
    func toggle(_ option: PollOption, in poll: CommunityPoll, userID: UUID) async {
        let mine = votes[poll.id, default: []].contains { $0.optionId == option.id && $0.userId == userID }
        do {
            if mine {
                try await client.unvote(optionID: option.id, userID: userID)
            } else {
                try await client.vote(pollID: poll.id, optionID: option.id, userID: userID)
            }
            await load(communityID: poll.communityId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func create(_ draft: PollDraft, communityID: UUID, userID: UUID) async -> Bool {
        do {
            try await client.create(draft, communityID: communityID, userID: userID)
            await load(communityID: communityID)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func close(_ poll: CommunityPoll) async {
        do { try await client.close(pollID: poll.id) } catch { lastError = error.localizedDescription }
        await load(communityID: poll.communityId)
    }

    func setComments(_ poll: CommunityPoll, enabled: Bool) async {
        do { try await client.setComments(pollID: poll.id, enabled: enabled) } catch { lastError = error.localizedDescription }
        await load(communityID: poll.communityId)
    }

    func delete(_ poll: CommunityPoll) async {
        do { try await client.delete(pollID: poll.id) } catch { lastError = error.localizedDescription }
        await load(communityID: poll.communityId)
    }
}

/// Zeitpunkt einer Terminfindung: „Sa., 3. Okt. · 19:00“ in Inselzeit.
enum PollFormat {
    static func slot(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: IslandTime.germanLocale, calendar: IslandTime.calendar, timeZone: IslandTime.timeZone)
        style = style.weekday(.abbreviated).day().month(.abbreviated)
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: IslandTime.germanLocale, calendar: IslandTime.calendar, timeZone: IslandTime.timeZone)
        return "\(date.formatted(style)) · \(date.formatted(time))"
    }

    static func deadline(_ date: Date) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: IslandTime.germanLocale, calendar: IslandTime.calendar, timeZone: IslandTime.timeZone)
        return date.formatted(style)
    }

    static func label(_ option: PollOption, kind: PollKind) -> String {
        if kind == .date, let startsAt = option.startsAt { return slot(startsAt) }
        return option.label
    }
}

/// Eine Umfrage als Karte: Frage, Status, Antworten mit Balken und Namen; Tippen stimmt ab.
struct PollCard: View {
    let poll: CommunityPoll
    let votes: [PollVote]
    let userID: UUID?
    let isAdmin: Bool
    let onToggle: (PollOption) -> Void
    let onClose: () -> Void
    let onDelete: () -> Void
    var commentCount = 0
    var onComments: () -> Void = {}
    var onToggleComments: () -> Void = {}
    @State private var confirmDelete = false

    private var isOpen: Bool { poll.isOpen() }
    /// Terminfindung grün, Umfragen mit Antworten magenta — auf einen Blick unterscheidbar.
    private var tint: Color { poll.kind == .date ? StedeTheme.duneGreen : StedeTheme.heather }
    /// Abstimmende Personen (nicht Stimmen) — Basis für die Prozente bei Mehrfachauswahl.
    private var voterCount: Int { Set(votes.map(\.userId)).count }
    private var maxVotes: Int { poll.options.map { count(for: $0) }.max() ?? 0 }

    private func count(for option: PollOption) -> Int { votes.filter { $0.optionId == option.id }.count }
    private func isMine(_ option: PollOption) -> Bool { votes.contains { $0.optionId == option.id && $0.userId == userID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: poll.kind == .date ? "calendar.badge.clock" : "chart.bar.fill", color: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(poll.question).font(.headline)
                    statusLine
                }
                Spacer(minLength: 0)
                if isAdmin { adminMenu }
            }
            if !poll.description.isEmpty {
                Text(poll.description).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(poll.options) { option in optionRow(option) }
            }
            HStack {
                Text(voterCount == 1 ? "1 Person hat abgestimmt" : "\(voterCount) Personen haben abgestimmt")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if poll.commentsEnabled {
                    Button(action: onComments) {
                        Label(commentCount > 0 ? "\(commentCount)" : "Kommentieren", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .accessibilityLabel(commentCount == 1 ? "1 Kommentar" : "\(commentCount) Kommentare")
                }
            }
        }
        .padding(StedeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard()
        .confirmationDialog("Umfrage löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive, action: onDelete)
        } message: {
            Text("Frage, Antworten und alle Stimmen werden entfernt.")
        }
    }

    private var statusLine: some View {
        var parts: [String] = []
        if poll.kind == .date { parts.append("Terminfindung") }
        if poll.multiple { parts.append("Mehrfachauswahl") }
        if !isOpen {
            parts.append("Beendet")
        } else if let closesAt = poll.closesAt {
            parts.append("bis \(PollFormat.deadline(closesAt))")
        }
        return Text(parts.isEmpty ? "Eine Antwort" : parts.joined(separator: " · "))
            .font(.caption).foregroundStyle(isOpen ? Color.secondary : StedeTheme.harborRed)
    }

    private var adminMenu: some View {
        Menu {
            if isOpen { Button("Umfrage beenden", systemImage: "lock", action: onClose) }
            Button(poll.commentsEnabled ? "Kommentare ausschalten" : "Kommentare erlauben",
                   systemImage: poll.commentsEnabled ? "bubble.left.and.exclamationmark.bubble.right" : "bubble.left.and.bubble.right",
                   action: onToggleComments)
            Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(StedeTheme.ink)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .accessibilityLabel("Umfrage verwalten")
    }

    private func optionRow(_ option: PollOption) -> some View {
        let votesHere = count(for: option)
        let share = voterCount > 0 ? Double(votesHere) / Double(voterCount) : 0
        let mine = isMine(option)
        let leading = !isOpen && votesHere > 0 && votesHere == maxVotes
        let names = votes.filter { $0.optionId == option.id }.compactMap { $0.profile?.displayName }.sorted()
        return Button {
            onToggle(option)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: mine ? (poll.multiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (poll.multiple ? "square" : "circle"))
                        .foregroundStyle(mine ? tint : Color.secondary)
                    Text(PollFormat.label(option, kind: poll.kind))
                        .fontWeight(leading ? .semibold : .regular)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text("\(votesHere)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.12))
                        Capsule().fill(tint.opacity(mine || leading ? 0.8 : 0.45))
                            .frame(width: max(geo.size.width * share, share > 0 ? 6 : 0))
                    }
                }
                .frame(height: 6)
                if !names.isEmpty {
                    Text(names.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(10)
            .background(StedeTheme.sand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(StedeCardButtonStyle())
        .foregroundStyle(.primary)
        .disabled(!isOpen || userID == nil)
        .accessibilityLabel("\(PollFormat.label(option, kind: poll.kind)), \(votesHere) Stimmen")
        .accessibilityAddTraits(mine ? .isSelected : [])
    }
}

/// Neue Umfrage: Frage, Art (Antworten / Terminfindung), Möglichkeiten, Mehrfachauswahl, Enddatum.
struct PollEditorView: View {
    let onSave: (PollDraft) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var description = ""
    @State private var kind: PollKind = .text
    @State private var multiple = false
    @State private var hasDeadline = false
    @State private var commentsEnabled = false
    @State private var closesAt = IslandTime.day(Date(), adding: 7)
    @State private var texts = ["", ""]
    @State private var slots = [EventEditorView.nextFullHour, EventEditorView.nextFullHour.addingTimeInterval(24 * 3600)]
    @State private var saving = false

    private var cleanTexts: [String] { texts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var canSave: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty && (kind == .text ? cleanTexts.count >= 2 : slots.count >= 2) && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Frage") {
                    TextField("Frage", text: $question, axis: .vertical).lineLimit(1 ... 3)
                    TextField("Beschreibung (optional)", text: $description, axis: .vertical).lineLimit(2 ... 5)
                }
                Section {
                    Picker("Art", selection: $kind.animation()) {
                        Text("Antworten").tag(PollKind.text)
                        Text("Terminfindung").tag(PollKind.date)
                    }
                    .pickerStyle(.segmented)
                }
                if kind == .text {
                    Section("Antworten") {
                        ForEach(texts.indices, id: \.self) { index in
                            TextField("Antwort \(index + 1)", text: $texts[index])
                        }
                        .onDelete { if texts.count > 2 { texts.remove(atOffsets: $0) } }
                        Button("Antwort hinzufügen", systemImage: "plus") { texts.append("") }
                    }
                } else {
                    Section {
                        ForEach(slots.indices, id: \.self) { index in
                            DatePicker("Vorschlag \(index + 1)", selection: $slots[index])
                        }
                        .onDelete { if slots.count > 2 { slots.remove(atOffsets: $0) } }
                        Button("Termin hinzufügen", systemImage: "plus") {
                            slots.append((slots.last ?? EventEditorView.nextFullHour).addingTimeInterval(24 * 3600))
                        }
                    } header: {
                        Text("Terminvorschläge")
                    } footer: {
                        Text("Mitglieder markieren alle Termine, an denen sie können.")
                    }
                }
                Section {
                    Toggle("Mehrfachauswahl", isOn: $multiple)
                    Toggle("Kommentare erlauben", isOn: $commentsEnabled)
                    Toggle("Enddatum", isOn: $hasDeadline.animation())
                    if hasDeadline { DatePicker("Endet am", selection: $closesAt, in: Date()...) }
                } footer: {
                    Text("Alle Mitglieder sehen, wer wofür gestimmt hat.")
                }
            }
            .onChange(of: kind) { if kind == .date { multiple = true } }
            .navigationTitle("Neue Umfrage")
            .stedeSheetForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Starten") { Task { await save() } }.disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let options: [(label: String, startsAt: Date?)] = kind == .text
            ? cleanTexts.map { ($0, nil) }
            : slots.sorted().map { ("", $0) }
        let draft = PollDraft(question: question.trimmingCharacters(in: .whitespaces), description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                              kind: kind, multiple: multiple, closesAt: hasDeadline ? closesAt : nil, commentsEnabled: commentsEnabled, options: options)
        if await onSave(draft) { dismiss() }
    }
}

/// Kommentare einer Umfrage als Sheet: oben die Frage, darunter der Verlauf wie bei Terminen.
struct PollCommentsSheet: View {
    let poll: CommunityPoll
    let canModerate: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    Text(poll.question).font(.title3.weight(.semibold)).fontDesign(.rounded)
                        .padding(.horizontal, 4)
                    EventCommentsSection(target: .poll(poll.id), canModerate: canModerate)
                }
                .padding()
            }
            .background(StedeTheme.sand)
            .navigationTitle("Kommentare")
            .stedeBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
