import StedeCore
import SwiftUI

/// Admin als Sheet im Stil des Profil-Sheets: Formular mit Abschnitten.
/// App-Admins sehen Gruppen-Anträge, Community-Admins die Mitgliedsanfragen.
struct AdminView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var model = AdminModel()

    var body: some View {
        NavigationStack {
            Form {
                if auth.isTenantAdmin {
                    Section("Gruppen-Anträge") {
                        if model.pendingCommunities.isEmpty {
                            Text(model.state == .loading ? "Lade …" : "Keine offenen Anträge.").foregroundStyle(.secondary)
                        }
                        ForEach(model.pendingCommunities) { community in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    CommunityAvatar(logoURL: community.logoURL, name: community.name)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(community.name).font(.headline).fontDesign(.rounded)
                                        StedeTagPill(text: community.joinPolicy == .open ? "offen" : "auf Anfrage", color: StedeTheme.mudflat)
                                    }
                                }
                                if !community.description.isEmpty {
                                    Text(community.description).font(.subheadline).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Button { Task { await model.decide(community: community, approve: true) } } label: {
                                        StedeColorChip(title: "Freigeben", symbol: "checkmark", color: StedeTheme.duneGreen, prominent: true)
                                    }
                                    Button { Task { await model.decide(community: community, approve: false) } } label: {
                                        StedeColorChip(title: "Ablehnen", symbol: "xmark", color: StedeTheme.harborRed)
                                    }
                                }
                                .buttonStyle(StedeCardButtonStyle())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if !auth.adminCommunityIDs.isEmpty {
                    Section("Mitgliedsanfragen") {
                        if model.requests.isEmpty {
                            Text(model.state == .loading ? "Lade …" : "Keine offenen Anfragen.").foregroundStyle(.secondary)
                        }
                        ForEach(model.requests, id: \.member.id) { request in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    PersonAvatar(url: request.member.profile?.avatarURL, name: request.member.profile?.displayName ?? "Mitglied", color: StedeTheme.sunAmber)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(request.member.profile?.displayName ?? "Mitglied").font(.headline).fontDesign(.rounded)
                                        StedeTagPill(text: request.community.name, color: StedeTheme.seaTeal)
                                        JoinMessageText(message: request.member.joinMessage)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Button { Task { await model.decide(request: request, accept: true) } } label: {
                                        StedeColorChip(title: "Bestätigen", symbol: "checkmark", color: StedeTheme.duneGreen, prominent: true)
                                    }
                                    Button { Task { await model.decide(request: request, accept: false) } } label: {
                                        StedeColorChip(title: "Ablehnen", symbol: "xmark", color: StedeTheme.harborRed)
                                    }
                                }
                                .buttonStyle(StedeCardButtonStyle())
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section {
                    Text(auth.isTenantAdmin
                         ? "Als App-Admin siehst du nur Anträge – keine Inhalte der Gruppen, außer du bist selbst Mitglied."
                         : "Anfragen an die Gruppen, die du leitest oder verwaltest.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if case .failed(let message) = model.state {
                    Section { Text(message).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
                }
                if let error = model.lastError {
                    Section { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
                }
            }
            .navigationTitle("Admin")
            .stedeSheetForm()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .refreshable { await load() }
            .task(id: "\(auth.isTenantAdmin)|\(auth.adminCommunityIDs.map(\.uuidString).joined())") { await load() }
        }
    }

    private func load() async {
        await model.load(tenantID: auth.tenant?.id, isTenantAdmin: auth.isTenantAdmin, adminCommunityIDs: auth.adminCommunityIDs)
    }
}
