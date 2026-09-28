#if os(iOS)
import StedeCore
import SwiftUI
import UIKit
import UserNotifications

/// Einstellungen → Benachrichtigungen: Erlaubnis von iOS, Anlässe (Termine, Umfragen,
/// Admin-Aufgaben) und stummgeschaltete Gruppen. Gespeichert in `push_settings`,
/// `push-send` filtert danach — gilt also für alle Geräte des Kontos.
struct NotificationSettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var settings = PushSettings()
    @State private var loaded = false
    @State private var groups: [Community] = []
    @State private var error: String?
    private let client = PushClient()

    var body: some View {
        Form {
            // Helles Petrol im Dark Mode nur für die Zeilen — die Leiste behält ihr dunkles Petrol.
            Group {
            Section {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    Label("Mitteilungen sind erlaubt", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(StedeTheme.duneGreen)
                case .denied:
                    Text("Mitteilungen sind für stede in den iOS-Einstellungen ausgeschaltet.")
                        .foregroundStyle(.secondary)
                    Button("iOS-Einstellungen öffnen", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                default:
                    Button("Mitteilungen erlauben", systemImage: "bell.badge") {
                        Task {
                            if let userID = auth.userID { await PushCenter.shared.enable(userID: userID, tenantID: auth.tenant?.id) }
                            await refreshStatus()
                        }
                    }
                }
            } header: {
                StedeFormHeader(title: "Mitteilungen", symbol: "bell.fill")
            }

            Section {
                Toggle("Neue Termine", isOn: binding(\.events))
                Toggle("Neue Umfragen", isOn: binding(\.polls))
                if auth.showsAdminTab {
                    Toggle("Beitrittsanfragen und neue Gruppen", isOn: binding(\.admin))
                }
            } header: {
                StedeFormHeader(title: "Worüber", symbol: "list.bullet")
            } footer: {
                Text("Gilt für alle deine Geräte. Was du selbst anlegst, meldet dir stede nicht.")
            }
            .disabled(!loaded)

            if !groups.isEmpty {
                Section {
                    ForEach(groups) { group in
                        Toggle(isOn: groupBinding(group.id)) {
                            HStack(spacing: 10) {
                                CommunityAvatar(logoURL: group.logoURL, name: group.name, side: 28)
                                Text(group.name).lineLimit(1)
                            }
                        }
                    }
                } header: {
                    StedeFormHeader(title: "Gruppen", symbol: "person.3.fill")
                } footer: {
                    Text("Ausgeschaltete Gruppen bleiben stumm – ihre Termine und Umfragen siehst du weiter in der App.")
                }
                .disabled(!loaded)
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
            }
            }
            .tint(StedeTheme.ink)
        }
        .navigationTitle("Benachrichtigungen")
        .stedeSheetForm()
        .task { await load() }
        // Zurück aus den iOS-Einstellungen: Status neu lesen.
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await refreshStatus() } } }
    }

    private func binding(_ keyPath: WritableKeyPath<PushSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0; save() })
    }

    /// An = nicht stummgeschaltet.
    private func groupBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { !settings.mutedCommunities.contains(id) }, set: { on in
            if on { settings.mutedCommunities.remove(id) } else { settings.mutedCommunities.insert(id) }
            save()
        })
    }

    private func load() async {
        await refreshStatus()
        guard let userID = auth.userID else { return }
        let active = Set(auth.memberships.filter { $0.status == .active }.map(\.communityId))
        // Gruppennamen: zuerst aus dem Zwischenspeicher der Gruppenliste, sonst frisch.
        var all = CommunityCache.load([Community].self, "communities", userID: userID) ?? []
        if all.isEmpty, let tenantID = auth.tenant?.id { all = (try? await CommunityClient().communities(tenantID: tenantID)) ?? [] }
        groups = all.filter { active.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        do {
            settings = try await client.settings(userID: userID)
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refreshStatus() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func save() {
        guard let userID = auth.userID else { return }
        let current = settings
        Task {
            do { try await client.save(current, userID: userID); error = nil } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
