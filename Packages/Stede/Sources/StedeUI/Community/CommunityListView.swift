import PhotosUI
import StedeCore
import SwiftUI

/// Tab „Community“: alle Communities der Gemeinde, eigene zuerst.
struct CommunityListView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model = CommunityListModel()
    @State private var showsAccount = false
    @State private var showsEditor = false
    @State private var showsAdmin = false
    @State private var showsInvite = false

    var body: some View {
        TabScreen(title: "Gruppen", showsDateNavigator: false) {
            await model.load(tenantID: auth.tenant?.id)
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    if !auth.isSignedIn {
                        InfoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Gruppen aus \(auth.tenant?.municipality ?? "deiner Gemeinde") mit eigenem Kalender – Verein, Nachbarschaft, Chor.")
                                    .foregroundStyle(.secondary)
                                Button { showsAccount = true } label: {
                                    StedeColorChip(title: "Anmelden", symbol: "person.crop.circle", color: StedeTheme.ink, prominent: true)
                                }
                                .buttonStyle(StedeCardButtonStyle())
                            }
                        }
                    }
                    if !mine.isEmpty {
                        StedeSectionHeader(title: "Meine Gruppen", symbol: "person.3.fill")
                        ForEach(mine) { community in
                            NavigationLink(value: community) { CommunityCard(community: community, membership: auth.membership(for: community.id)) }
                                .buttonStyle(StedeCardButtonStyle()).foregroundStyle(.primary)
                        }
                    }
                    if !others.isEmpty {
                        StedeSectionHeader(title: mine.isEmpty ? "Gruppen" : "Weitere", symbol: "person.2.fill")
                        ForEach(others) { community in
                            NavigationLink(value: community) { CommunityCard(community: community, membership: nil) }
                                .buttonStyle(StedeCardButtonStyle()).foregroundStyle(.primary)
                        }
                    } else if mine.isEmpty, model.state == .loaded || model.state == .empty {
                        StedeSectionHeader(title: "Gruppen", symbol: "person.2.fill")
                        InfoCard { Text("Noch keine Gruppe in \(auth.tenant?.municipality ?? "dieser Gemeinde"). Leg die erste an.").foregroundStyle(.secondary) }
                    }
                    if auth.isSignedIn {
                        StedeSectionHeader(title: "Mitmachen", symbol: "plus.circle.fill")
                        Button { showsInvite = true } label: {
                            JoinRow(symbol: "key.fill", color: StedeTheme.seaTeal, title: "Einladungscode eingeben",
                                    detail: "Du hast einen Code für eine Gruppe bekommen.")
                        }
                        .buttonStyle(StedeCardButtonStyle()).foregroundStyle(.primary)
                        Button { showsEditor = true } label: {
                            JoinRow(symbol: "plus", color: StedeTheme.duneGreen, title: "Gruppe gründen",
                                    detail: "Für Verein, Nachbarschaft oder Chor – die Gemeinde gibt sie frei.")
                        }
                        .buttonStyle(StedeCardButtonStyle()).foregroundStyle(.primary)
                    }
                    if case .failed(let message) = model.state { Text(message).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
                }
                .padding()
            }
        }
        .navigationDestination(for: Community.self) { CommunityDetailView(community: $0) }
        .navigationDestination(item: $invited) { CommunityDetailView(community: $0) }
        .toolbar {
            if auth.showsAdminTab {
                ToolbarItem(placement: .primaryAction) {
                    Button { showsAdmin = true } label: {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.white)
                    }
                    .tint(.white)
                    .accessibilityLabel("Admin")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showsAccount = true } label: {
                    if let url = auth.profile?.avatarURL {
                        PersonAvatar(url: url, name: auth.profile?.displayName ?? "", side: 28)
                    } else {
                        Image(systemName: auth.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                            .foregroundStyle(.white)
                    }
                }
                .tint(.white)
                .accessibilityLabel(auth.isSignedIn ? "Konto" : "Anmelden")
            }
        }
        .sheet(isPresented: $showsInvite) {
            InviteCodeSheet { code in
                guard let community = try? await CommunityClient().communityByInvite(code: code) else { return false }
                if !model.communities.contains(where: { $0.id == community.id }) { model.communities.append(community) }
                showsInvite = false
                invited = community
                return true
            }
        }
        .sheet(isPresented: $showsAccount) { AccountView() }
        .sheet(isPresented: $showsAdmin) { AdminView() }
        .sheet(isPresented: $showsEditor) {
            CommunityEditorView(existing: nil) { _ in Task { await model.load(tenantID: auth.tenant?.id); await auth.refresh() } }
        }
        .task(id: "\(auth.tenant?.id.uuidString ?? "")|\(auth.userID?.uuidString ?? "")") {
            await model.load(tenantID: auth.tenant?.id)
        }
    }

    private var mine: [Community] {
        model.communities.filter { auth.membership(for: $0.id) != nil || $0.createdBy == auth.userID }
    }

    private var others: [Community] {
        model.communities.filter { auth.membership(for: $0.id) == nil && $0.createdBy != auth.userID && $0.status == .approved }
    }

    @State private var invited: Community?
}

/// Kleines Sheet für den Einladungscode: Erklärung, Feld, Öffnen; Fehler direkt darunter.
private struct InviteCodeSheet: View {
    /// Liefert `false`, wenn es zum Code keine Gruppe gibt.
    let open: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var notFound = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gib den Code ein, den du von der Gruppe bekommen hast.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    StedeTextField(placeholder: "Code", text: $code)
                        .focused($focused)
                        .onSubmit { Task { await submit() } }
                    Button { Task { await submit() } } label: {
                        StedeColorChip(title: "Öffnen", color: StedeTheme.seaTeal, prominent: canSubmit)
                    }
                    .buttonStyle(StedeCardButtonStyle()).disabled(!canSubmit)
                }
                if notFound {
                    Text("Zu diesem Code gibt es keine Gruppe. Bitte prüfe die Schreibweise.")
                        .font(.footnote).foregroundStyle(StedeTheme.harborRed)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StedeTheme.sand)
            .navigationTitle("Einladungscode")
            .stedeBar()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .onChange(of: code) { notFound = false }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(230)])
    }

    private var trimmed: String { code.trimmingCharacters(in: .whitespaces) }
    private var canSubmit: Bool { trimmed.count >= 6 && !busy }

    private func submit() async {
        guard canSubmit else { return }
        busy = true
        notFound = !(await open(trimmed))
        busy = false
    }
}

/// Einzeilige Karte unter „Mitmachen“: Symbol, Titel, kurze Erklärung, Pfeil.
private struct JoinRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            StedeIconChip(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.leading)
        .stedeRowCard()
    }
}

struct CommunityCard: View {
    let community: Community
    let membership: CommunityMember?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CommunityAvatar(logoURL: community.logoURL, name: community.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(community.name).font(.headline).fontDesign(.rounded)
                if !community.description.isEmpty {
                    Text(community.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let count = community.memberCount { StedeTagPill(text: count == 1 ? "1 Mitglied" : "\(count) Mitglieder", color: StedeTheme.seaTeal) }
                    if community.status == .pending { StedeTagPill(text: "wartet auf Freigabe", color: StedeTheme.sunAmber) }
                    if let membership {
                        switch membership.status {
                        case .pending: StedeTagPill(text: "Anfrage offen", color: StedeTheme.sunAmber)
                        case .active: StedeTagPill(text: membership.role == .member ? "Mitglied" : (membership.role == .owner ? "Leitung" : "Admin"), color: StedeTheme.duneGreen)
                        case .banned: EmptyView()
                        }
                    }
                    if community.joinPolicy == .approval && membership == nil { StedeTagPill(text: "auf Anfrage", color: StedeTheme.mudflat) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(StedeTheme.cardPadding).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
    }
}

/// Community anlegen oder Einstellungen ändern.
struct CommunityEditorView: View {
    let existing: Community?
    let onSave: (Community?) -> Void
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var visibility: CommunityVisibility = .listed
    @State private var joinPolicy: CommunityJoinPolicy = .approval
    @State private var error: String?
    @State private var saving = false
    @State private var logoItem: PhotosPickerItem?
    @State private var logoData: Data?
    @State private var removeLogo = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Logo") {
                    HStack(spacing: 14) {
                        if let logoData, let image = EventPhotoResizer.image(from: logoData) {
                            image.resizable().scaledToFill().frame(width: 72, height: 72).clipShape(StedeTheme.chipShape)
                        } else if let path = existing?.logoPath, !removeLogo {
                            CommunityAvatar(logoURL: Backend.communityLogoURL(path: path), name: name, side: 72)
                        } else {
                            CommunityAvatar(logoURL: nil, name: name.isEmpty ? "?" : name, side: 72)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $logoItem, matching: .images) {
                                Label(logoData == nil && (existing?.logoPath == nil || removeLogo) ? "Logo auswählen" : "Anderes Logo", systemImage: "photo")
                            }
                            if logoData != nil || (existing?.logoPath != nil && !removeLogo) {
                                Button("Logo entfernen", role: .destructive) { logoData = nil; logoItem = nil; removeLogo = true }
                            }
                        }
                    }
                }
                Section("Gruppe") {
                    TextField("Name", text: $name)
                    TextField("Beschreibung", text: $description, axis: .vertical).lineLimit(2 ... 5)
                }
                Section("Regeln") {
                    Picker("Sichtbarkeit", selection: $visibility) {
                        Text("In der Liste").tag(CommunityVisibility.listed)
                        Text("Nur per Einladungscode").tag(CommunityVisibility.hidden)
                    }
                    Picker("Beitritt", selection: $joinPolicy) {
                        Text("Jeder sofort").tag(CommunityJoinPolicy.open)
                        Text("Admins bestätigen").tag(CommunityJoinPolicy.approval)
                    }
                }
                if existing == nil {
                    Section { Text("Nach dem Antrag gibt die Gemeinde-App die Gruppe frei. Du bist dann die Leitung.").font(.footnote).foregroundStyle(.secondary) }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) } }
            }
            .navigationTitle(existing == nil ? "Neue Gruppe" : "Einstellungen")
            .stedeSheetForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Beantragen" : "Sichern") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).count < 3 || saving)
                }
            }
            .onChange(of: logoItem) {
                Task {
                    if let item = logoItem, let data = try? await item.loadTransferable(type: Data.self) {
                        logoData = EventPhotoResizer.jpeg(from: data, maxSide: 512)
                        removeLogo = false
                    }
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name; description = existing.description
                    visibility = existing.visibility; joinPolicy = existing.joinPolicy
                }
            }
        }
    }

    private func save() async {
        guard let userID = auth.userID, let tenant = auth.tenant else { return }
        saving = true
        defer { saving = false }
        let client = CommunityClient()
        do {
            if let existing {
                var logoPath: String? = removeLogo ? nil : existing.logoPath
                if let logoData { logoPath = try await client.uploadCommunityLogo(logoData, communityID: existing.id) }
                try await client.updateCommunity(id: existing.id, name: name, description: description, visibility: visibility, joinPolicy: joinPolicy, logoPath: logoPath)
                if let old = existing.logoPath, old != logoPath { try? await client.deleteCommunityLogo(path: old) }
                onSave(nil)
            } else {
                var created = try await client.createCommunity(tenantID: tenant.id, name: name.trimmingCharacters(in: .whitespaces), description: description, visibility: visibility, joinPolicy: joinPolicy, userID: userID)
                if let logoData {
                    let path = try await client.uploadCommunityLogo(logoData, communityID: created.id)
                    try await client.setCommunityLogo(id: created.id, logoPath: path)
                    created.logoPath = path
                }
                onSave(created)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
