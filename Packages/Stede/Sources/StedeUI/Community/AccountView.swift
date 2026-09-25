import AuthenticationServices
import PhotosUI
import StedeCore
import SwiftUI

/// Anmeldung (Apple, Magic Link) und Kontoeinstellungen.
struct AccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var magicLinkSent = false
    @State private var usesPassword = false
    @State private var password = ""
    @State private var name = ""
    @State private var calendarToken: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var uploadingPhoto = false
    @State private var showPhotoPicker = false
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
                // Fehler nur beim Anmelden zeigen; angemeldet sind sie überholt.
                if !auth.isSignedIn, let error = auth.lastError {
                    Section { Text(error).font(.footnote).foregroundStyle(StedeTheme.harborRed) }
                }
            }
            .navigationTitle(auth.isSignedIn ? "Konto" : "Anmelden")
            .stedeSheetForm()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onAppear { auth.lastError = nil }
            .task(id: auth.userID) {
                auth.lastError = nil
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
            Text("Ein Konto gilt für alle Gemeinde-Apps. Du brauchst es nur für Gruppen und ihre Termine.")
                .font(.subheadline).foregroundStyle(.secondary)
            if AuthStore.appleSignInAvailable {
                SignInWithAppleButton(.signIn) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { await auth.completeAppleSignIn(result) }
                }
                .frame(height: 48)
                .listRowInsets(EdgeInsets())
            }
        }
        Section(AuthStore.appleSignInAvailable ? "Oder per E-Mail" : "Per E-Mail") {
            TextField("E-Mail-Adresse", text: $email)
                .textContentType(.emailAddress)
                #if !os(macOS)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            if usesPassword {
                SecureField("Passwort", text: $password)
                    .textContentType(.password)
                Button("Anmelden") {
                    Task { _ = await auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
                }
                .disabled(email.isEmpty || password.isEmpty || auth.isLoading)
            } else {
                Button(magicLinkSent ? "Link gesendet – bitte E-Mail öffnen" : "Anmeldelink schicken") {
                    Task { magicLinkSent = await auth.sendMagicLink(email: email.trimmingCharacters(in: .whitespaces)) }
                }
                .disabled(email.isEmpty || auth.isLoading || magicLinkSent)
            }
        }
        Section {
            // Für Konten mit Passwort (z. B. Prüfkonten von Apple und Google).
            Button(usesPassword ? "Stattdessen Anmeldelink schicken" : "Mit Passwort anmelden") {
                withAnimation { usesPassword.toggle(); password = "" }
            }
            .font(.footnote)
        }
    }

    @ViewBuilder private var signedInSections: some View {
        Section {
            HStack(spacing: 14) {
                Menu {
                    Button(auth.profile?.avatarURL == nil ? "Profilbild auswählen" : "Anderes Profilbild", systemImage: "photo") {
                        showPhotoPicker = true
                    }
                    if auth.profile?.avatarURL != nil {
                        Button("Profilbild entfernen", systemImage: "trash", role: .destructive) {
                            Task { uploadingPhoto = true; await auth.updateAvatar(nil); uploadingPhoto = false }
                        }
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        PersonAvatar(url: auth.profile?.avatarURL, name: name.isEmpty ? "?" : name, side: 64)
                            .overlay { if uploadingPhoto { ProgressView() } }
                        Image(systemName: "camera.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, StedeTheme.deep)
                    }
                }
                .disabled(uploadingPhoto)
                TextField("Anzeigename", text: $name)
                    .font(.headline)
                    .onSubmit { Task { await auth.updateDisplayName(name) } }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) {
                guard let item = photoItem else { return }
                Task {
                    uploadingPhoto = true
                    if let data = try? await item.loadTransferable(type: Data.self), let jpeg = EventPhotoResizer.jpeg(from: data, maxSide: 512) {
                        await auth.updateAvatar(jpeg)
                    }
                    photoItem = nil
                    uploadingPhoto = false
                }
            }
        } header: {
            Text("Profil")
        } footer: {
            Text("Name und Bild sehen nur Mitglieder deiner Gruppen. Tippe auf das Bild, um es zu ändern.")
        }
        Section {
            if let token = calendarToken {
                Link(destination: Backend.webcalURL(token: token)) {
                    Label("Meine Termine", systemImage: "calendar.badge.checkmark")
                }
                Link(destination: Backend.webcalURL(token: token, scope: "communities")) {
                    Label("Alle Termine meiner Gruppen", systemImage: "calendar")
                }
                ShareLink(item: Backend.feedURL(token: token)) {
                    Label("Abo-Link teilen", systemImage: "square.and.arrow.up")
                }
            } else {
                ProgressView()
            }
        } header: {
            Text("Kalender abonnieren")
        } footer: {
            Text("Die Termine erscheinen im Kalender deines Geräts und aktualisieren sich von selbst.")
        }
        Section {
            Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right") { Task { await auth.signOut(); dismiss() } }
            Button("Konto löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                .alert("Konto löschen?", isPresented: $confirmDelete) {
                    Button("Abbrechen", role: .cancel) {}
                    Button("Endgültig löschen", role: .destructive) {
                        Task { if await auth.deleteAccount() { dismiss() } }
                    }
                } message: {
                    Text("Dein Konto, dein Profilbild und alle Mitgliedschaften werden gelöscht. Das lässt sich nicht rückgängig machen.")
                }
        }
    }
}
