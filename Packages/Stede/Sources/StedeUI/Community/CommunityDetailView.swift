import PhotosUI
import StedeCore
import SwiftUI

/// Eine Community: Umschalter Termine · Umfragen · Mitglieder · Einstellungen wie bei der Bahn;
/// wer nicht Mitglied ist, sieht nur den Kopf mit Beitritt.
struct CommunityDetailView: View {
    private enum Section: CaseIterable, Hashable {
        case events, polls, members, settings

        var title: String {
            switch self {
            case .events: "Termine"
            case .polls: "Umfragen"
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
    @State private var openedEvent: CommunityEvent?
    @State private var showsNewEvent = false
    @State private var showsAccount = false
    @State private var busy = false
    @State private var confirmLeave = false
    @State private var showsJoinRequest = false
    @State private var polls = PollsModel()
    @State private var showsNewPoll = false

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
                            case .polls: pollsSection
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
        .toolbar {
            if isActiveMember, section == .events {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsNewEvent = true } label: { Image(systemName: "plus").foregroundStyle(.white) }
                        .tint(.white)
                        .accessibilityLabel("Termin anlegen")
                }
            }
            if isAdmin, section == .polls {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsNewPoll = true } label: { Image(systemName: "plus").foregroundStyle(.white) }
                        .tint(.white)
                        .accessibilityLabel("Umfrage anlegen")
                }
            }
        }
        .task(id: "\(auth.userID?.uuidString ?? "")|\(isActiveMember)") { await reload() }
        .sheet(isPresented: $showsEditor) {
            CommunityEditorView(existing: model.community) { _ in Task { await reload() } }
        }
        .sheet(isPresented: $showsNewEvent) {
            EventEditorView(communityID: model.community.id, existing: nil) { draft in await model.save(draft, editing: nil) }
        }
        .sheet(item: $editingEvent) { event in
            EventEditorView(communityID: model.community.id, existing: event) { draft in await model.save(draft, editing: event.id) } onCancelEvent: {
                await model.cancel(event: event)
            }
        }
        .sheet(isPresented: $showsAccount) { AccountView() }
        .sheet(isPresented: $showsNewPoll) {
            PollEditorView { draft in
                guard let userID = auth.userID else { return false }
                return await polls.create(draft, communityID: model.community.id, userID: userID)
            }
        }
        .sheet(isPresented: $showsJoinRequest) {
            JoinRequestSheet(communityName: model.community.name) { message in
                guard let userID = auth.userID else { return false }
                do {
                    try await model.join(userID: userID, message: message)
                } catch { return false }
                await auth.refresh()
                await reload()
                return true
            }
        }
        .sheet(item: $openedEvent) { event in
            CommunityEventDetailView(
                info: eventInfo(event), helperCount: model.helperCounts[event.id] ?? 0,
                participation: model.myParticipations[event.id], isSignedIn: auth.isSignedIn,
                onParticipate: { status, helping in
                    Task { if let userID = auth.userID { await model.setParticipation(event: event, userID: userID, status: status, helping: helping) } }
                },
                signIn: { showsAccount = true },
                onEdit: canEdit(event) ? { openedEvent = nil; editingEvent = event } : nil,
                showsParticipants: canEdit(event)
            )
        }
    }

    private func reload() async {
        await model.load(userID: auth.userID, isMember: isActiveMember)
        if isActiveMember, polls.polls != nil { await polls.load(communityID: model.community.id) }
    }

    // MARK: Kopf (Nicht-Mitglieder)

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CommunityAvatar(logoURL: model.community.logoURL, name: model.community.name)
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
        .padding(StedeTheme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
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
                // Mit Freigabe: erst die optionale Kurzvorstellung, sonst sofort beitreten.
                if model.community.joinPolicy == .open {
                    Task { busy = true; try? await model.join(userID: auth.userID!); await auth.refresh(); await reload(); busy = false }
                } else {
                    showsJoinRequest = true
                }
            } label: {
                StedeColorChip(title: model.community.joinPolicy == .open ? "Beitreten" : "Beitritt anfragen", symbol: "person.badge.plus", color: StedeTheme.duneGreen, prominent: true)
            }
            .buttonStyle(StedeCardButtonStyle()).disabled(busy)
        }
    }

    // MARK: Termine

    /// Oben „Frühere Termine“ wie im Kalender: jeder Tipp holt 20 vergangene Termine dazu,
    /// die chronologisch über den kommenden stehen.
    @ViewBuilder private var eventsSection: some View {
        if model.hasMorePast { earlierButton }
        if let past = model.pastEvents {
            if past.isEmpty {
                Text("Keine früheren Termine.").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            ForEach(past.reversed()) { event in eventCard(event) }
        }
        if model.events.isEmpty { InfoCard { Text("Noch keine anstehenden Termine.").foregroundStyle(.secondary) } }
        ForEach(model.events) { event in eventCard(event) }
    }

    private var earlierButton: some View {
        Button {
            Task { if model.pastEvents == nil { await model.loadPastEvents() } else { await model.loadMorePastEvents() } }
        } label: {
            HStack(spacing: 6) {
                if model.loadingPast { ProgressView().controlSize(.small) } else { Image(systemName: "chevron.up") }
                Text("Frühere Termine")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .stedeSelectionChip(isSelected: false)
        }
        .buttonStyle(StedeCardButtonStyle())
        .disabled(model.loadingPast)
    }

    // MARK: Umfragen

    @ViewBuilder private var pollsSection: some View {
        if let list = polls.polls {
            if list.isEmpty {
                InfoCard {
                    Text(isAdmin ? "Noch keine Umfrage. Starte eine mit +." : "Noch keine Umfrage in dieser Gruppe.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(list) { poll in
                PollCard(
                    poll: poll, votes: polls.votes[poll.id] ?? [], userID: auth.userID, isAdmin: isAdmin,
                    onToggle: { option in Task { if let userID = auth.userID { await polls.toggle(option, in: poll, userID: userID) } } },
                    onClose: { Task { await polls.close(poll) } },
                    onDelete: { Task { await polls.delete(poll) } }
                )
            }
            if let error = polls.lastError { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                .task { await polls.load(communityID: model.community.id) }
        }
    }

    private func eventCard(_ event: CommunityEvent) -> some View {
        CommunityEventCard(
            info: eventInfo(event), helperCount: model.helperCounts[event.id] ?? 0,
            participation: model.myParticipations[event.id], isSignedIn: auth.isSignedIn,
            onParticipate: { status, helping in
                Task { if let userID = auth.userID { await model.setParticipation(event: event, userID: userID, status: status, helping: helping) } }
            },
            signIn: { showsAccount = true },
            onOpen: { openedEvent = event }
        )
    }

    private func canEdit(_ event: CommunityEvent) -> Bool { isAdmin || event.createdBy == auth.userID }

    /// Innerhalb der Community fehlt dem Termin der Join auf die Community — Name und Logo kommen von hier.
    private func eventInfo(_ event: CommunityEvent) -> CommunityEventInfo {
        var copy = event
        copy.community = CommunityEvent.CommunityName(name: model.community.name, logoPath: model.community.logoPath)
        return CommunityEventInfo(copy)
    }

    // MARK: Mitglieder

    @ViewBuilder private var membersSection: some View {
        if isAdmin, !model.pendingMembers.isEmpty {
            StedeSectionHeader(title: "Anfragen", symbol: "person.badge.clock")
            ForEach(model.pendingMembers) { member in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        PersonAvatar(url: member.profile?.avatarURL, name: member.profile?.displayName ?? "Mitglied", color: StedeTheme.sunAmber)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.profile?.displayName ?? "Mitglied").font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                            JoinMessageText(message: member.joinMessage)
                        }
                    }
                    HStack(spacing: 8) {
                        Button { Task { await model.setMember(member, status: .active) } } label: {
                            StedeColorChip(title: "Bestätigen", symbol: "checkmark", color: StedeTheme.duneGreen, prominent: true)
                        }
                        Button { Task { await model.setMember(member, status: .banned) } } label: {
                            StedeColorChip(title: "Ablehnen", symbol: "xmark", color: StedeTheme.harborRed)
                        }
                    }
                }
                .buttonStyle(StedeCardButtonStyle())
                .stedeRowCard()
            }
        }
        StedeSectionHeader(title: "Mitglieder", symbol: "person.3.fill")
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
            .stedeRowCard()
        }
    }

    private func memberRow(_ member: CommunityMember) -> some View {
        HStack(spacing: 12) {
            PersonAvatar(url: member.profile?.avatarURL, name: member.profile?.displayName ?? "Mitglied", color: member.role == .member ? StedeTheme.ink : StedeTheme.heather)
            Text(member.profile?.displayName ?? "Mitglied").font(.subheadline.weight(.semibold)).fontDesign(.rounded)
            Spacer()
            if member.role != .member { StedeTagPill(text: member.role == .owner ? "Leitung" : "Admin", color: StedeTheme.heather) }
            if isAdmin, member.role != .owner, member.userId != auth.userID {
                Menu {
                    if member.role == .member { Button("Zum Admin machen") { Task { await model.setMember(member, role: .admin) } } }
                    else { Button("Admin-Rolle entziehen") { Task { await model.setMember(member, role: .member) } } }
                    Button("Entfernen", role: .destructive) { Task { await model.setMember(member, status: .banned) } }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(StedeTheme.ink) }
            }
        }
        .stedeRowCard()
    }

    // MARK: Einstellungen

    @ViewBuilder private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CommunityAvatar(logoURL: model.community.logoURL, name: model.community.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.community.name).font(.headline).fontDesign(.rounded)
                    pills
                }
            }
            if !model.community.description.isEmpty {
                Text(model.community.description).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(model.community.visibility == .listed ? "In der Gruppenliste sichtbar" : "Nur per Einladungscode", systemImage: model.community.visibility == .listed ? "eye" : "eye.slash")
                Label(model.community.joinPolicy == .open ? "Beitritt sofort" : "Admins bestätigen den Beitritt", systemImage: "person.badge.plus")
                if let membership { Label("Deine Rolle: \(membership.role == .owner ? "Leitung" : membership.role == .admin ? "Admin" : "Mitglied")", systemImage: "person.text.rectangle") }
            }
            .font(.caption)
            if isAdmin {
                Button { showsEditor = true } label: {
                    StedeColorChip(title: "Bearbeiten", symbol: "pencil", color: StedeTheme.ink, prominent: true)
                }
                .buttonStyle(StedeCardButtonStyle())
            }
        }
        .padding(StedeTheme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).stedeCard()

        if isAdmin, let userID = auth.userID {
            HeaderImagesManager(communityID: model.community.id, userID: userID)
        }

        if !isOwner {
            Button { confirmLeave = true } label: {
                StedeColorChip(title: "Gruppe verlassen", symbol: "rectangle.portrait.and.arrow.right", color: StedeTheme.harborRed)
            }
            .buttonStyle(StedeCardButtonStyle()).disabled(busy)
            .confirmationDialog("„\(model.community.name)“ verlassen?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Verlassen", role: .destructive) {
                    Task { try? await model.leave(userID: auth.userID!); await auth.refresh(); section = .events; await reload() }
                }
            }
        } else {
            Text("Als Leitung kannst du die Gruppe nicht verlassen – übergib die Rolle oder archiviere sie.")
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
                        // Einstellungen als schmales Zahnrad, die Reiter teilen sich den Rest.
                        if item == .settings {
                            Image(systemName: "gearshape.fill")
                                .frame(width: StedeTheme.chipHeight)
                                .stedeSelectionChip(isSelected: selection == item)
                        } else {
                            Text(item.title)
                                .frame(maxWidth: .infinity)
                                .stedeSelectionChip(isSelected: selection == item)
                        }
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            }
            .padding(.horizontal, StedeTheme.SelectionRow.horizontalInset)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
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
    let communityID: UUID
    let existing: CommunityEvent?
    let onSave: (CommunityEventDraft) async -> Bool
    var onCancelEvent: (() async -> Void)?
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var startsAt = EventEditorView.nextFullHour
    @State private var hasEnd = false
    @State private var endsAt = EventEditorView.nextFullHour.addingTimeInterval(3600)
    @State private var isPublic = false
    @State private var wantsHelpers = false
    @State private var commentsEnabled = false
    @State private var helpersNeeded = 3
    @State private var saving = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var existingImagePath: String?
    /// Foto beim Öffnen — wird nach dem Sichern gelöscht, wenn ersetzt (Standardbilder nie).
    @State private var originalImagePath: String?
    @State private var removePhoto = false
    @State private var error: String?
    @State private var headerImages: [CommunityHeaderImage] = []
    /// Gruppe des Termins — nur bei kreisweiten Gruppen lässt sich die Reichweite wählen.
    @State private var community: Community?
    @State private var countywideReach = true
    @State private var targetTenants: Set<UUID> = []

    /// Neue Termine beginnen zur nächsten vollen Stunde (10:23 → 11:00), nicht zur aktuellen Minute.
    static var nextFullHour: Date {
        let cal = IslandTime.calendar
        let hour = cal.dateInterval(of: .hour, for: Date())?.start ?? Date()
        return cal.date(byAdding: .hour, value: 1, to: hour) ?? hour
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Foto") {
                    if let photoData, let image = EventPhotoResizer.image(from: photoData) {
                        image.resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 160)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                            .listRowInsets(EdgeInsets())
                    } else if let existingImagePath, !removePhoto {
                        EventPhoto(url: Backend.eventPhotoURL(path: existingImagePath), height: 160)
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                            .listRowInsets(EdgeInsets())
                    }
                    if !headerImages.isEmpty {
                        HeaderImagePicker(images: headerImages, selectedPath: photoData == nil && !removePhoto ? existingImagePath : nil) { image in
                            existingImagePath = image.path; photoData = nil; photoItem = nil; removePhoto = false
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil && (existingImagePath == nil || removePhoto) ? "Eigenes Foto auswählen" : "Anderes eigenes Foto", systemImage: "photo")
                    }
                    if photoData != nil || (existingImagePath != nil && !removePhoto) {
                        Button("Foto entfernen", role: .destructive) { photoData = nil; photoItem = nil; removePhoto = true }
                    }
                }
                Section("Termin") {
                    TextField("Titel", text: $title)
                    DatePicker("Beginn", selection: $startsAt)
                        .onChange(of: startsAt) { if endsAt < startsAt { endsAt = startsAt.addingTimeInterval(3600) } }
                    Toggle("Ende (optional)", isOn: $hasEnd.animation())
                    if hasEnd { DatePicker("Ende", selection: $endsAt, in: startsAt...) }
                    TextField("Ort", text: $location)
                    TextField("Beschreibung", text: $description, axis: .vertical).lineLimit(3 ... 8)
                }
                Section("Helfer") {
                    Toggle("Helfer gesucht", isOn: $wantsHelpers.animation())
                    if wantsHelpers {
                        Stepper("Anzahl: \(helpersNeeded)", value: $helpersNeeded, in: 1 ... 99)
                    }
                    Text("Mitglieder und – bei öffentlichen Terminen – alle Nutzer können sich als Helfer eintragen, bis die Zahl erreicht ist.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Kommentare") {
                    Toggle("Kommentare erlauben", isOn: $commentsEnabled)
                        .disabled(isPublic)
                    Text(isPublic
                         ? "Kommentare gibt es nur bei internen Terminen."
                         : "Mitglieder der Gruppe können unter dem Termin Fragen stellen und sich abstimmen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Öffentlich im Kalender der Gemeinde", isOn: $isPublic)
                        .onChange(of: isPublic) { if isPublic { commentsEnabled = false } }
                    Text("Öffentlich zeigt Titel, Zeit, Ort und Gruppenname allen Nutzern der App. Mitglieder und Zusagen bleiben intern.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if isPublic, let community, community.isCountywide {
                    reachSection(home: community.tenantId)
                }
                if existing != nil, existing?.cancelledAt == nil, let onCancelEvent {
                    Section { Button("Termin absagen", role: .destructive) { Task { await onCancelEvent(); dismiss() } } }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) } }
            }
            .onChange(of: photoItem) {
                Task {
                    if let item = photoItem, let data = try? await item.loadTransferable(type: Data.self) {
                        photoData = EventPhotoResizer.jpeg(from: data)
                        removePhoto = false
                    }
                }
            }
            .task { headerImages = (try? await CommunityClient().headerImages(communityID: communityID)) ?? [] }
            .task { community = try? await CommunityClient().community(id: communityID) }
            .navigationTitle(existing == nil ? "Neuer Termin" : "Termin bearbeiten")
            .stedeSheetForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving || lacksTarget)
                }
            }
            .onAppear {
                if let existing {
                    title = existing.title; description = existing.description; location = existing.location ?? ""
                    startsAt = existing.startsAt; hasEnd = existing.endsAt != nil; endsAt = existing.endsAt ?? existing.startsAt.addingTimeInterval(3600)
                    isPublic = existing.visibility == .public
                    existingImagePath = existing.imagePath
                    originalImagePath = existing.imagePath
                    wantsHelpers = existing.helpersNeeded > 0
                    helpersNeeded = max(existing.helpersNeeded, 1)
                    commentsEnabled = existing.commentsEnabled
                    countywideReach = existing.targetTenants == nil
                    targetTenants = Set(existing.targetTenants ?? [])
                }
            }
        }
    }

    /// Kreisweit oder nur ausgewählte Gemeinden — auch die Heimatgemeinde der Gruppe ist abwählbar.
    @ViewBuilder private func reachSection(home: UUID) -> some View {
        Section {
            Picker("Reichweite", selection: $countywideReach.animation()) {
                Text("Kreisweit").tag(true)
                Text("Gemeinden wählen").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: countywideReach) {
                // Beim Umschalten ist die eigene Gemeinde vorgewählt.
                if !countywideReach, targetTenants.isEmpty { targetTenants = [home] }
            }
            if !countywideReach {
                ForEach(Tenants.all.filter { $0.tenantID != nil }) { tenant in
                    let id = tenant.tenantID!
                    Toggle(isOn: Binding(
                        get: { targetTenants.contains(id) },
                        set: { if $0 { targetTenants.insert(id) } else { targetTenants.remove(id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tenant.municipality)
                            if id == home { Text("Heimatgemeinde").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        } header: {
            Text("Sichtbar in")
        } footer: {
            Text(countywideReach
                 ? "Der Termin erscheint im Kalender aller Ammerland-Gemeinden."
                 : targetTenants.isEmpty ? "Wähle mindestens eine Gemeinde." : "Der Termin erscheint nur in den gewählten Gemeinden.")
        }
    }

    /// Öffentlicher Termin einer kreisweiten Gruppe ohne gewählte Gemeinde wäre nirgends sichtbar.
    private var lacksTarget: Bool {
        isPublic && community?.isCountywide == true && !countywideReach && targetTenants.isEmpty
    }

    private func save() async {
        guard let userID = auth.userID else { return }
        saving = true
        defer { saving = false }
        let client = CommunityClient()
        var imagePath: String? = removePhoto ? nil : existingImagePath
        if let photoData {
            do {
                imagePath = try await client.uploadEventPhoto(photoData, communityID: communityID)
            } catch {
                self.error = "Foto konnte nicht hochgeladen werden: \(error.localizedDescription)"
                return
            }
        }
        let draft = CommunityEventDraft(
            communityId: communityID, title: title.trimmingCharacters(in: .whitespaces), description: description,
            startsAt: startsAt, endsAt: hasEnd ? endsAt : nil, location: location.isEmpty ? nil : location,
            imagePath: imagePath, helpersNeeded: wantsHelpers ? helpersNeeded : 0, commentsEnabled: commentsEnabled && !isPublic, visibility: isPublic ? .public : .members,
            targetTenants: community?.isCountywide == true && !countywideReach ? Array(targetTenants) : nil,
            createdBy: existing?.createdBy ?? userID
        )
        if await onSave(draft) {
            // Altes Foto räumen, wenn ersetzt oder entfernt.
            if let old = originalImagePath, old != imagePath { try? await client.deleteEventPhoto(path: old) }
            dismiss()
        }
    }
}

/// Standardbilder der Community als waagerechte Reihe: antippen setzt das Kopfbild.
struct HeaderImagePicker: View {
    let images: [CommunityHeaderImage]
    let selectedPath: String?
    let onSelect: (CommunityHeaderImage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Standardbild").font(.subheadline.weight(.semibold)).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(images) { image in
                        Button { onSelect(image) } label: {
                            VStack(spacing: 4) {
                                RemoteImage(url: image.url) { Rectangle().fill(StedeTheme.seaTeal.opacity(0.12)) }
                                    .frame(width: 96, height: 64)
                                    .clipShape(StedeTheme.chipShape)
                                    .overlay {
                                        if image.path == selectedPath {
                                            StedeTheme.chipShape.strokeBorder(StedeTheme.ink, lineWidth: 3)
                                        }
                                    }
                                Text(image.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(width: 96)
                            }
                        }
                        .buttonStyle(StedeCardButtonStyle())
                        .accessibilityLabel("Standardbild \(image.label)")
                        .accessibilityAddTraits(image.path == selectedPath ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Standardbilder verwalten (Leitung und Admins): Raster, hinzufügen mit Namen, löschen per Kontextmenü.
struct HeaderImagesManager: View {
    let communityID: UUID
    let userID: UUID
    @State private var images: [CommunityHeaderImage] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingData: Data?
    @State private var label = ""
    @State private var askLabel = false
    @State private var busy = false
    @State private var error: String?
    private let client = CommunityClient()
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StedeSectionHeader(title: "Standardbilder", symbol: "photo.on.rectangle")
            Text("Mitglieder können sie beim Anlegen eines Termins als Kopfbild wählen.")
                .font(.footnote).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(images) { image in
                    VStack(spacing: 4) {
                        RemoteImage(url: image.url) { Rectangle().fill(StedeTheme.seaTeal.opacity(0.12)) }
                            .frame(height: 64).frame(maxWidth: .infinity)
                            .clipShape(StedeTheme.chipShape)
                        Text(image.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .contextMenu {
                        Button("Löschen", systemImage: "trash", role: .destructive) { Task { await delete(image) } }
                    }
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    VStack(spacing: 4) {
                        Image(systemName: busy ? "hourglass" : "plus").font(.title3.weight(.semibold))
                            .frame(height: 64).frame(maxWidth: .infinity)
                            .background(StedeTheme.seaTeal.opacity(0.12), in: StedeTheme.chipShape)
                            .foregroundStyle(StedeTheme.ink)
                        Text("Hinzufügen").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .disabled(busy)
            }
            if !images.isEmpty {
                Text("Zum Löschen lange auf ein Bild drücken.").font(.caption2).foregroundStyle(.tertiary)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
        }
        .padding(StedeTheme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
        .task { await load() }
        .onChange(of: pickerItem) {
            Task {
                guard let item = pickerItem, let raw = try? await item.loadTransferable(type: Data.self) else { return }
                pendingData = EventPhotoResizer.jpeg(from: raw, maxSide: 1600)
                pickerItem = nil
                label = ""
                askLabel = pendingData != nil
            }
        }
        .alert("Name des Bildes", isPresented: $askLabel) {
            TextField("z. B. Rathaus", text: $label)
            Button("Abbrechen", role: .cancel) { pendingData = nil }
            Button("Hinzufügen") { Task { await add() } }
        }
    }

    private func load() async {
        images = (try? await client.headerImages(communityID: communityID)) ?? []
    }

    private func add() async {
        guard let data = pendingData else { return }
        busy = true; defer { busy = false; pendingData = nil }
        do {
            let name = label.trimmingCharacters(in: .whitespaces)
            try await client.addHeaderImage(data, label: name.isEmpty ? "Bild \(images.count + 1)" : name,
                                            communityID: communityID, userID: userID, sortOrder: (images.map(\.sortOrder).max() ?? 0) + 1)
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func delete(_ image: CommunityHeaderImage) async {
        do { try await client.deleteHeaderImage(image); await load() } catch { self.error = error.localizedDescription }
    }
}

/// Beitrittsantrag mit optionaler Kurzvorstellung, die die Admins beim Freischalten sehen.
private struct JoinRequestSheet: View {
    let communityName: String
    /// Liefert `false`, wenn das Senden fehlschlug.
    let send: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sending = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    Text("Die Admins von „\(communityName)“ bestätigen neue Mitglieder. Stell dich gern kurz vor – das ist freiwillig.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    VStack(alignment: .trailing, spacing: 6) {
                        TextField("Kurze Vorstellung (optional)", text: $message, axis: .vertical)
                            .lineLimit(3 ... 8)
                            .focused($focused)
                            .onChange(of: message) { if message.count > 500 { message = String(message.prefix(500)) } }
                        Text("\(message.count)/500").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    .padding(StedeTheme.cardPadding)
                    .stedeCard()
                    Button {
                        Task {
                            sending = true
                            failed = !(await send(message))
                            sending = false
                            if !failed { dismiss() }
                        }
                    } label: {
                        StedeColorChip(title: sending ? "Wird gesendet …" : "Anfrage senden", symbol: "paperplane.fill", color: StedeTheme.duneGreen, prominent: true)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StedeCardButtonStyle())
                    .disabled(sending)
                    if failed {
                        Text("Die Anfrage konnte nicht gesendet werden. Bitte versuche es noch einmal.")
                            .font(.footnote).foregroundStyle(StedeTheme.harborRed)
                    }
                }
                .padding()
            }
            .background(StedeTheme.sand)
            .navigationTitle("Beitritt anfragen")
            .stedeBar()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Kurzvorstellung aus dem Beitrittsantrag, in Anführungszeichen unter dem Namen.
struct JoinMessageText: View {
    let message: String?

    var body: some View {
        if let message, !message.isEmpty {
            Text("„\(message)“")
                .font(.subheadline)
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
