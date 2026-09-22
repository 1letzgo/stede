import StedeCore
import SwiftUI

/// Tab „Admin“: Freigaben für App-Admins, Mitgliedsanfragen für Community-Admins.
struct AdminView: View {
    @Environment(AuthStore.self) private var auth
    @State private var model = AdminModel()

    var body: some View {
        TabScreen(title: "Admin", showsDateNavigator: false) {
            await load()
        } content: {
            LoadStateView(state: model.state, emptyMessage: "Nichts offen – keine Anträge, keine Anfragen.") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                        if !model.pendingCommunities.isEmpty {
                            StedeSectionHeader(title: "Community-Anträge", symbol: "checkmark.seal")
                            ForEach(model.pendingCommunities) { community in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 12) {
                                        StedeIconChip(symbol: "person.3.fill", color: StedeTheme.seaTeal)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(community.name).font(.headline).fontDesign(.rounded)
                                            StedeTagPill(text: community.joinPolicy == .open ? "offen" : "auf Anfrage", color: StedeTheme.mudflat)
                                        }
                                    }
                                    if !community.description.isEmpty { Text(community.description).font(.subheadline).foregroundStyle(.secondary) }
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
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
                            }
                        }
                        if !model.requests.isEmpty {
                            StedeSectionHeader(title: "Mitgliedsanfragen", symbol: "person.badge.clock")
                            ForEach(model.requests, id: \.member.id) { request in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(alignment: .top, spacing: 12) {
                                        StedeIconChip(symbol: "person.fill.questionmark", color: StedeTheme.sunAmber)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(request.member.profile?.displayName ?? "Mitglied").font(.headline).fontDesign(.rounded)
                                            StedeTagPill(text: request.community.name, color: StedeTheme.seaTeal)
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
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading).stedeCard()
                            }
                        }
                        if let error = model.lastError { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
                        SourceFooter(text: auth.isTenantAdmin ? "Als App-Admin siehst du nur Anträge – keine Inhalte der Communities." : "Anfragen deiner Communities")
                    }
                    .padding()
                }
            }
        }
        .task(id: "\(auth.isTenantAdmin)|\(auth.adminCommunityIDs.map(\.uuidString).joined())") { await load() }
    }

    private func load() async {
        await model.load(tenantID: auth.tenant?.id, isTenantAdmin: auth.isTenantAdmin, adminCommunityIDs: auth.adminCommunityIDs)
    }
}
