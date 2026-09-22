import AuthenticationServices
import StedeCore
import SwiftUI

/// Anmeldung (Apple, Magic Link) und Kontoeinstellungen.
struct AccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var magicLinkSent = false
    @State private var name = ""
    @State private var calendarToken: String?
    @State private var confirmDelete = false
    @State private var page: BrowserPage?
    private let client = CommunityClient()

    var body: some View {
        NavigationStack {
            Form {
                if auth.isSignedIn {
                    signedInSections
                } else {
                    signInSections
                }
                if let error = auth.lastError {
                    Section { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
                }
            }
            .navigationTitle(auth.isSignedIn ? "Konto" : "Anmelden")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
            }
            .task(id: auth.userID) {
                name = auth.profile?.displayName ?? ""
                calendarToken = nil
                if let userID = auth.userID {
                    calendarToken = try? await client.calendarToken(userID: userID)
                }
            }
            .sheet(item: $page) { InAppBrowser(url: $0.url) }
        }
    }

    @ViewBuilder private var signInSections: some View {
        Section {
            Text("Ein Konto gilt für alle Gemeinde-Apps. Du brauchst es nur für Communities und ihre Termine.")
                .font(.subheadline).foregroundStyle(.secondary)
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await auth.completeAppleSignIn(result) }
            }
            .frame(height: 48)
            .listRowInsets(EdgeInsets())
        }
        Section("Oder per E-Mail") {
            TextField("E-Mail-Adresse", text: $email)
                .textContentType(.emailAddress)
                #if !os(macOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            Button(magicLinkSent ? "Link gesendet – bitte E-Mail öffnen" : "Anmeldelink schicken") {
                Task { magicLinkSent = await auth.sendMagicLink(email: email.trimmingCharacters(in: .whitespaces)) }
            }
            .disabled(email.isEmpty || auth.isLoading || magicLinkSent)
        }
    }

    @ViewBuilder private var signedInSections: some View {
        Section("Profil") {
            TextField("Anzeigename", text: $name)
                .onSubmit { Task { await auth.updateDisplayName(name) } }
            Text("Name und Bild sehen nur Mitglieder deiner Communities.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Kalender-Abo") {
            Text("Termine, bei denen du zugesagt hast, als Abo im Systemkalender – aktualisiert sich von selbst.")
                .font(.footnote).foregroundStyle(.secondary)
            if let token = calendarToken {
                Link("Meine Termine abonnieren", destination: Backend.webcalURL(token: token))
                Link("Alle Termine meiner Communities abonnieren", destination: Backend.webcalURL(token: token, scope: "communities"))
                ShareLink("Abo-Link teilen", item: Backend.feedURL(token: token))
                Button("Link erneuern (alte Abos verlieren den Zugriff)", role: .destructive) {
                    Task { if let userID = auth.userID { calendarToken = try? await client.rotateCalendarToken(userID: userID) } }
                }
            } else {
                ProgressView()
            }
        }
        Section {
            Button("Abmelden") { Task { await auth.signOut(); dismiss() } }
            Button("Konto löschen", role: .destructive) { confirmDelete = true }
                .confirmationDialog("Konto und alle Mitgliedschaften löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Endgültig löschen", role: .destructive) {
                        Task { if await auth.deleteAccount() { dismiss() } }
                    }
                }
        }
    }
}
