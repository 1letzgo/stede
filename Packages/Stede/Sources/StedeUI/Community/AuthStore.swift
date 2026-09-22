import AuthenticationServices
import CryptoKit
import Foundation
import StedeCore
import Supabase

/// Anmeldung und alles, was am Konto hängt: Profil, Mandant, Rollen,
/// Mitgliedschaften. Ein Konto gilt über alle Gemeinde-Apps.
@Observable
final class AuthStore {
    /// Erst true, wenn die App-ID die Capability „Sign in with Apple“ hat und das
    /// Entitlement gesetzt ist — sonst bleibt der Apple-Button verborgen.
    static let appleSignInAvailable = false

    private(set) var userID: UUID?
    private(set) var profile: Profile?
    private(set) var tenant: Tenant?
    private(set) var isTenantAdmin = false
    private(set) var memberships: [CommunityMember] = []
    private(set) var isLoading = false
    var lastError: String?

    private let client = CommunityClient()
    private var currentNonce: String?
    private var listener: Task<Void, Never>?

    var isSignedIn: Bool { userID != nil }

    /// Communities, in denen der Nutzer Owner oder Admin ist — steuern den Tab „Admin“.
    var adminCommunityIDs: [UUID] {
        memberships.filter { $0.status == .active && ($0.role == .owner || $0.role == .admin) }.map(\.communityId)
    }

    var showsAdminTab: Bool { isTenantAdmin || !adminCommunityIDs.isEmpty }

    func membership(for communityID: UUID) -> CommunityMember? {
        memberships.first { $0.communityId == communityID }
    }

    /// Beim Start: Mandant laden, Session beobachten.
    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in Backend.client.auth.authStateChanges {
                guard [.initialSession, .signedIn, .signedOut, .tokenRefreshed, .userUpdated].contains(event) else { continue }
                await self.apply(session: session)
            }
        }
        Task { await loadTenant() }
    }

    private func loadTenant() async {
        do { tenant = try await client.tenant() } catch { lastError = error.localizedDescription }
    }

    private func apply(session: Session?) async {
        userID = session?.user.id
        guard let userID else {
            profile = nil; memberships = []; isTenantAdmin = false
            return
        }
        await refresh(userID: userID)
    }

    func refresh() async {
        guard let userID else { return }
        await refresh(userID: userID)
    }

    private func refresh(userID: UUID) async {
        if tenant == nil { await loadTenant() }
        do {
            profile = try await client.myProfile(userID: userID)
            memberships = try await client.myMemberships(userID: userID)
            if let tenant { isTenantAdmin = try await client.isTenantAdmin(tenantID: tenant.id) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { lastError = error.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else { lastError = "Apple hat kein Token geliefert."; return }
            isLoading = true
            defer { isLoading = false }
            do {
                try await Backend.client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
                // Der Name kommt nur beim allerersten Login mit — gleich ins Profil.
                if let name = credential.fullName, let userID = Backend.client.auth.currentUser?.id {
                    let full = [name.givenName, name.familyName].compactMap { $0 }.joined(separator: " ")
                    if !full.isEmpty { try? await client.updateDisplayName(userID: userID, name: full) }
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0 ..< length).map { _ in charset[Int.random(in: 0 ..< charset.count)] })
    }

    // MARK: Magic Link

    func sendMagicLink(email: String) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            try await Backend.client.auth.signInWithOTP(email: email, redirectTo: Backend.redirectURL)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Rückkehr per Deep-Link (`stede://auth-callback?...`).
    func handle(url: URL) async {
        do { try await Backend.client.auth.session(from: url) } catch { lastError = error.localizedDescription }
    }

    // MARK: Profil, Abmelden, Löschen

    func updateDisplayName(_ name: String) async {
        guard let userID else { return }
        do {
            try await client.updateDisplayName(userID: userID, name: name)
            profile = try await client.myProfile(userID: userID)
        } catch { lastError = error.localizedDescription }
    }

    func signOut() async {
        do { try await Backend.client.auth.signOut() } catch { lastError = error.localizedDescription }
    }

    func deleteAccount() async -> Bool {
        do {
            try await client.deleteAccount()
            try? await Backend.client.auth.signOut()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
