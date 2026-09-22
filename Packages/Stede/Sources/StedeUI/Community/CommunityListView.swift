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
    @State private var inviteCode = ""

    var body: some View {
        TabScreen(title: "Community", showsDateNavigator: false) {
            await model.load(tenantID: auth.tenant?.id)
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    if !auth.isSignedIn {
                        InfoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Communities sind Gruppen aus \(auth.tenant?.municipality ?? "deiner Gemeinde") mit eigenem Kalender – Verein, Nachbarschaft, Chor.")
                                    .foregroundStyle(.secondary)
                                Button { showsAccount = true } label: {
                                    StedeColorChip(title: "Anmelden", symbol: "person.crop.circle", color: StedeTheme.ink, prominent: true)
                                }
                                .buttonStyle(StedeCardButtonStyle())
                            }
                        }
                    }
                    if !mine.isEmpty {
                        StedeSectionHeader(title: "Meine Communities", symbol: "person.3.fill")
                        ForEach(mine) { community in
                            NavigationLink(value: community) { CommunityCard(community: community, membership: auth.membership(for: community.id)) }
                                .buttonStyle(StedeCardButtonStyle()).foregroundStyle(.primary)
                        }
                    }
                    if !others.isEmpty {
                        StedeSectionHeader(title: mine.isEmpty ? "Communities" : "Weitere", symbol: "person.2.fill")
                        ForEach(others) { community in
                            NavigationLink(value: community) { CommunityCard(community: community, membership: nil) }
                                .buttonStyle(StedeCardButtonStyle()).foregroundStyle(.primary)
                        }
                    } else if mine.isEmpty, model.state == .loaded || model.state == .empty {
                        StedeSectionHeader(title: "Communities", symbol: "person.2.fill")
                        InfoCard { Text("Noch keine Community in \(auth.tenant?.municipality ?? "dieser Gemeinde"). Leg die erste an.").foregroundStyle(.secondary) }
                    }
                    if auth.isSignedIn {
                        StedeSectionHeader(title: "Mitmachen", symbol: "plus.circle.fill")
                        InfoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Einladungscode erhalten?").font(.subheadline.weight(.semibold))
                                HStack(spacing: 8) {
                                    StedeTextField(placeholder: "Code", text: $inviteCode)
                                    Button { Task { await openInvite() } } label: {
                                        StedeColorChip(title: "Öffnen", color: StedeTheme.seaTeal, prominent: inviteCode.count >= 6)
                                    }
                                    .buttonStyle(StedeCardButtonStyle()).disabled(inviteCode.count < 6)
                                }
                                Rectangle().fill(.separator).frame(height: 1)
                                Text("Verein, Nachbarschaft oder Chor ohne eigene Community? Die Gemeinde gibt neue Communities frei.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button { showsEditor = true } label: {
                                    StedeColorChip(title: "Neue Community beantragen", symbol: "plus", color: StedeTheme.ink, prominent: true)
                                }
                                .buttonStyle(StedeCardButtonStyle())
                            }
                        }
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
                    Image(systemName: auth.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                        .foregroundStyle(.white)
                }
                .tint(.white)
                .accessibilityLabel(auth.isSignedIn ? "Konto" : "Anmelden")
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
    private func openInvite() async {
        if let community = try? await CommunityClient().communityByInvite(code: inviteCode.trimmingCharacters(in: .whitespaces)) {
            if !model.communities.contains(where: { $0.id == community.id }) { model.communities.append(community) }
            inviteCode = ""
            invited = community
        }
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
                Section("Community") {
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
                    Section { Text("Nach dem Antrag gibt die Gemeinde-App die Community frei. Du bist dann die Leitung.").font(.footnote).foregroundStyle(.secondary) }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) } }
            }
            .navigationTitle(existing == nil ? "Neue Community" : "Einstellungen")
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
