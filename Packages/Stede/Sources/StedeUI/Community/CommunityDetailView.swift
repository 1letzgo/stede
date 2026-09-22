import StedeCore
import SwiftUI

/// Eine Community: Umschalter Termine · Mitglieder · Einstellungen wie bei der Bahn;
/// wer nicht Mitglied ist, sieht nur den Kopf mit Beitritt.
struct CommunityDetailView: View {
    private enum Section: CaseIterable, Hashable {
        case events, members, settings

        var title: String {
            switch self {
            case .events: "Termine"
            case .members: "Mitglieder"
            case .settings: "Einstellungen"
            }
        }
    }

    @Environment(AuthStore.self) private var auth
    @State private var model: CommunityDetailModel
    @State private var section: Section = .events
    @State private var showsEditor = false
    @State private var editingEvent: CommunityEvent?
    @State private var showsNewEvent = false
    @State private var showsAccount = false
    @State private var busy = false
    @State private var confirmLeave = false

    init(community: Community) {
        _model = State(initialValue: CommunityDetailModel(community: community))
    }

    private var membership: CommunityMember? { auth.membership(for: model.community.id) }
    private var isActiveMember: Bool { membership?.status == .active }
    private var isAdmin: Bool { isActiveMember && (membership?.role == .owner || membership?.role == .admin) }
    private var isOwner: Bool { isActiveMember && membership?.role == .owner }

    var body: some View {
        TabScreen(title: model.community.name, showsDateNavigator: false) {
            await reload()
        } content: {
            VStack(spacing: 0) {
                if isActiveMember {
                    SectionSwitcher(selection: $section)
                        .padding(.top)
                        .padding(.bottom, StedeTheme.cardSpacing)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                        if !isActiveMember {
                            header
                        } else {
                            switch section {
                            case .events: eventsSection
                            case .members: membersSection
                            case .settings: settingsSection
                            }
                        }
                        if let error = model.lastError { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
                    }
                    .padding([.horizontal, .bottom])
                    .padding(.top, isActiveMember ? 0 : 16)
                }
            }
        }
        .task(id: "\(auth.userID?.uuidString ?? "")|\(isActiveMember)") { await reload() }
        .sheet(isPresented: $showsEditor) {
            CommunityEditorView(existing: model.community) { _ in Task { await reload() } }
        }
        .sheet(isPresented: $showsNewEvent) {
            EventEditorView(community: model.community, existing: nil) { draft in await model.save(draft, editing: nil) }
        }
        .sheet(item: $editingEvent) { event in
            EventEditorView(community: model.community, existing: event) { draft in await model.save(draft, editing: event.id) } onCancelEvent: {
                await model.cancel(event: event)
            }
        }
        .sheet(isPresented: $showsAccount) { AccountView() }
    }

    private func reload() async {
        await model.load(userID: auth.userID, isMember: isActiveMember)
    }

    // MARK: Kopf (Nicht-Mitglieder)

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: "person.3.fill", color: StedeTheme.seaTeal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.community.name).font(.headline).fontDesign(.rounded)
                    pills
                }
            }
            if !model.community.description.isEmpty {
                Text(model.community.description).font(.subheadline).foregroundStyle(.secondary)
            }
            joinControls
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
    }

    private var pills: some View {
        HStack(spacing: 6) {
            if let count = model.community.memberCount { StedeTagPill(text: count == 1 ? "1 Mitglied" : "\(count) Mitglieder", color: StedeTheme.seaTeal) }
            StedeTagPill(text: model.community.joinPolicy == .open ? "offen" : "auf Anfrage", color: StedeTheme.mudflat)
            if model.community.status == .pending { StedeTagPill(text: "wartet auf Freigabe", color: StedeTheme.sunAmber) }
        }
    }

    @ViewBuilder private var joinControls: some View {
        if !auth.isSignedIn {
            Button { showsAccount = true } label: {
                StedeColorChip(title: "Anmelden, um beizutreten", symbol: "person.crop.circle", color: StedeTheme.ink, prominent: true)
            }
            .buttonStyle(StedeCardButtonStyle())
        } else if let membership, membership.status == .pending {
            Label("Anfrage gestellt – ein Admin bestätigt dich.", systemImage: "hourglass").font(.footnote).foregroundStyle(.secondary)
        } else if membership == nil, model.community.status == .approved {
            Button {
                Task { busy = true; try? await model.join(userID: auth.userID!); await auth.refresh(); await reload(); busy = false }
            } label: {
                StedeColorChip(title: model.community.joinPolicy == .open ? "Beitreten" : "Beitritt anfragen", symbol: "person.badge.plus", color: StedeTheme.duneGreen, prominent: true)
            }
            .buttonStyle(StedeCardButtonStyle()).disabled(busy)
        }
    }

    // MARK: Termine

    @ViewBuilder private var eventsSection: some View {
        if model.events.isEmpty { InfoCard { Text("Noch keine Termine.").foregroundStyle(.secondary) } }
        ForEach(model.events) { event in
            CommunityEventCard(event: event, participation: model.myParticipations[event.id]) { status in
                Task { if let userID = auth.userID { await model.setParticipation(event: event, userID: userID, status: status) } }
            } onEdit: {
                editingEvent = event
            } canEdit: {
                isAdmin || event.createdBy == auth.userID
            }
        }
        Button { showsNewEvent = true } label: {
            StedeColorChip(title: "Termin anlegen", symbol: "plus", color: StedeTheme.ink, prominent: true)
        }
        .buttonStyle(StedeCardButtonStyle())
    }

    // MARK: Mitglieder

    @ViewBuilder private var membersSection: some View {
        if isAdmin, !model.pendingMembers.isEmpty {
            StedeSectionHeader(title: "Anfragen", symbol: "person.badge.clock")
            ForEach(model.pendingMembers) { member in
                HStack(spacing: 12) {
                    StedeIconChip(symbol: "person.fill.questionmark", color: StedeTheme.sunAmber, side: 30)
                    Text(member.profile?.displayName ?? "Mitglied").font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                    Spacer()
                    Button { Task { await model.setMember(member, status: .active) } } label: {
                        StedeColorChip(title: "Bestätigen", symbol: "checkmark", color: StedeTheme.duneGreen, prominent: true)
                    }
                    Button { Task { await model.setMember(member, status: .banned) } } label: {
                        StedeColorChip(title: "Ablehnen", symbol: "xmark", color: StedeTheme.harborRed)
                    }
                }
                .buttonStyle(StedeCardButtonStyle())
                .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
            }
            StedeSectionHeader(title: "Mitglieder", symbol: "person.3.fill")
        }
        ForEach(model.activeMembers) { member in memberRow(member) }
        if isAdmin, let code = model.community.inviteCode {
            HStack(spacing: 8) {
                Label("Einladungscode \(code)", systemImage: "key.fill").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ShareLink(item: "Tritt „\(model.community.name)“ in der \(auth.tenant?.name ?? "stede")-App bei – Einladungscode \(code)") {
                    StedeActionChip(title: "Einladen", symbol: "square.and.arrow.up")
                }
                .buttonStyle(StedeCardButtonStyle())
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
        }
    }

    private func memberRow(_ member: CommunityMember) -> some View {
        HStack(spacing: 12) {
            StedeIconChip(symbol: "person.fill", color: member.role == .member ? StedeTheme.ink : StedeTheme.heather, side: 30)
            Text(member.profile?.displayName ?? "Mitglied").font(.subheadline.weight(.semibold)).fontDesign(.rounded)
            Spacer()
            if member.role != .member { StedeTagPill(text: member.role == .owner ? "Owner" : "Admin", color: StedeTheme.heather) }
            if isAdmin, member.role != .owner, member.userId != auth.userID {
                Menu {
                    if member.role == .member { Button("Zum Admin machen") { Task { await model.setMember(member, role: .admin) } } }
                    else { Button("Admin-Rolle entziehen") { Task { await model.setMember(member, role: .member) } } }
                    Button("Entfernen", role: .destructive) { Task { await model.setMember(member, status: .banned) } }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(StedeTheme.ink) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
    }

    // MARK: Einstellungen

    @ViewBuilder private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: "person.3.fill", color: StedeTheme.seaTeal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.community.name).font(.headline).fontDesign(.rounded)
                    pills
                }
            }
            if !model.community.description.isEmpty {
                Text(model.community.description).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(model.community.visibility == .listed ? "In der Community-Liste sichtbar" : "Nur per Einladungscode", systemImage: model.community.visibility == .listed ? "eye" : "eye.slash")
                Label(model.community.joinPolicy == .open ? "Beitritt sofort" : "Admins bestätigen den Beitritt", systemImage: "person.badge.plus")
                if let membership { Label("Deine Rolle: \(membership.role == .owner ? "Owner" : membership.role == .admin ? "Admin" : "Mitglied")", systemImage: "person.text.rectangle") }
            }
            .font(.caption)
            if isAdmin {
                Button { showsEditor = true } label: {
                    StedeColorChip(title: "Bearbeiten", symbol: "pencil", color: StedeTheme.ink, prominent: true)
                }
                .buttonStyle(StedeCardButtonStyle())
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).stedeCard()

        if !isOwner {
            Button { confirmLeave = true } label: {
                StedeColorChip(title: "Community verlassen", symbol: "rectangle.portrait.and.arrow.right", color: StedeTheme.harborRed)
            }
            .buttonStyle(StedeCardButtonStyle()).disabled(busy)
            .confirmationDialog("„\(model.community.name)“ verlassen?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Verlassen", role: .destructive) {
                    Task { try? await model.leave(userID: auth.userID!); await auth.refresh(); section = .events; await reload() }
                }
            }
        } else {
            Text("Als Owner kannst du die Community nicht verlassen – übergib die Rolle oder archiviere sie.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    /// Drei gleich breite Chips wie der Richtungsumschalter der Bahn.
    private struct SectionSwitcher: View {
        @Binding var selection: Section

        var body: some View {
            HStack(spacing: StedeTheme.SelectionRow.spacing) {
                ForEach(Section.allCases, id: \.self) { item in
                    Button {
                        selection = item
                    } label: {
                        Text(item.title)
                            .frame(maxWidth: .infinity)
                            .stedeSelectionChip(isSelected: selection == item)
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, StedeTheme.SelectionRow.horizontalInset)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }
}

struct CommunityEventCard: View {
    let event: CommunityEvent
    let participation: ParticipationStatus?
    let onParticipate: (ParticipationStatus?) -> Void
    let onEdit: () -> Void
    let canEdit: () -> Bool

    private static let dateFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .weekday(.abbreviated).day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    private static let timeFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    private var tint: Color { event.cancelledAt != nil ? StedeTheme.harborRed : StedeTheme.seaTeal }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: event.cancelledAt != nil ? "calendar.badge.exclamationmark" : "calendar", color: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.headline).fontDesign(.rounded).strikethrough(event.cancelledAt != nil)
                    HStack(spacing: 6) {
                        StedeTagPill(text: event.startsAt.formatted(Self.dateFormat) + (event.endsAt.map { "–\($0.formatted(Self.timeFormat))" } ?? ""), color: tint)
                        if event.cancelledAt != nil { StedeTagPill(text: "abgesagt", color: StedeTheme.harborRed) }
                        else if event.isPublic { StedeTagPill(text: "öffentlich", color: StedeTheme.duneGreen) }
                    }
                }
                Spacer(minLength: 8)
                if canEdit() {
                    Button { onEdit() } label: { StedeActionChip(title: "Bearbeiten", symbol: "pencil") }
                        .buttonStyle(StedeCardButtonStyle())
                }
            }
            if !event.description.isEmpty { Text(event.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(4) }
            if let location = event.location, !location.isEmpty {
                Label { Text(location) } icon: { Image(systemName: "mappin.and.ellipse").foregroundStyle(tint) }.font(.caption)
            }
            if event.cancelledAt == nil {
                ParticipationChips(participation: participation, onParticipate: onParticipate)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).stedeCard(highlighted: participation == .going)
    }
}

/// Ich komme · Vielleicht · Absage — grün, gelb, rot; nochmal tippen hebt die Wahl auf.
struct ParticipationChips: View {
    let participation: ParticipationStatus?
    let onParticipate: (ParticipationStatus?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach([ParticipationStatus.going, .maybe, .declined], id: \.self) { status in
                Button {
                    onParticipate(participation == status ? nil : status)
                } label: {
                    StedeColorChip(title: label(for: status), symbol: symbol(for: status), color: color(for: status), isSelected: participation == status)
                }
                .buttonStyle(StedeCardButtonStyle())
                .accessibilityAddTraits(participation == status ? .isSelected : [])
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func label(for status: ParticipationStatus) -> String {
        switch status {
        case .going: "Ich komme"
        case .maybe: "Vielleicht"
        case .declined: "Absage"
        }
    }

    private func symbol(for status: ParticipationStatus) -> String {
        switch status {
        case .going: "checkmark"
        case .maybe: "questionmark"
        case .declined: "xmark"
        }
    }

    private func color(for status: ParticipationStatus) -> Color {
        switch status {
        case .going: StedeTheme.duneGreen
        case .maybe: StedeTheme.sunAmber
        case .declined: StedeTheme.harborRed
        }
    }
}

/// Termin anlegen oder bearbeiten; Veröffentlichen schaltet ihn in den Stadt-Kalender.
struct EventEditorView: View {
    let community: Community
    let existing: CommunityEvent?
    let onSave: (CommunityEventDraft) async -> Bool
    var onCancelEvent: (() async -> Void)?
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var startsAt = Date().addingTimeInterval(3600)
    @State private var hasEnd = false
    @State private var endsAt = Date().addingTimeInterval(7200)
    @State private var isPublic = false
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    TextField("Titel", text: $title)
                    DatePicker("Beginn", selection: $startsAt)
                        .onChange(of: startsAt) { if endsAt < startsAt { endsAt = startsAt.addingTimeInterval(3600) } }
                    Toggle("Ende (optional)", isOn: $hasEnd.animation())
                    if hasEnd { DatePicker("Ende", selection: $endsAt, in: startsAt...) }
                    TextField("Ort", text: $location)
                    TextField("Beschreibung", text: $description, axis: .vertical).lineLimit(3 ... 8)
                }
                Section {
                    Toggle("Öffentlich im Kalender der Gemeinde", isOn: $isPublic)
                    Text("Öffentlich zeigt Titel, Zeit, Ort und Community-Name allen Nutzern der App. Mitglieder und Zusagen bleiben intern.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if existing != nil, existing?.cancelledAt == nil, let onCancelEvent {
                    Section { Button("Termin absagen", role: .destructive) { Task { await onCancelEvent(); dismiss() } } }
                }
            }
            .navigationTitle(existing == nil ? "Neuer Termin" : "Termin bearbeiten")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                if let existing {
                    title = existing.title; description = existing.description; location = existing.location ?? ""
                    startsAt = existing.startsAt; hasEnd = existing.endsAt != nil; endsAt = existing.endsAt ?? existing.startsAt.addingTimeInterval(3600)
                    isPublic = existing.visibility == .public
                }
            }
        }
    }

    private func save() async {
        guard let userID = auth.userID else { return }
        saving = true
        let draft = CommunityEventDraft(
            communityId: community.id, title: title.trimmingCharacters(in: .whitespaces), description: description,
            startsAt: startsAt, endsAt: hasEnd ? endsAt : nil, location: location.isEmpty ? nil : location,
            visibility: isPublic ? .public : .members, createdBy: existing?.createdBy ?? userID
        )
        if await onSave(draft) { dismiss() }
        saving = false
    }
}
