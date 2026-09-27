package de.letzgo.stede.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import de.letzgo.stede.data.Backend
import de.letzgo.stede.data.CommunityApi
import de.letzgo.stede.data.Member
import de.letzgo.stede.data.Profile
import de.letzgo.stede.data.Tenant
import de.letzgo.stede.data.Tenants
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Anmeldung, Profil, Mandant, Rollen — wie AuthStore in iOS. */
object Session {
    var userId by mutableStateOf<String?>(null); private set
    var profile by mutableStateOf<Profile?>(null); private set
    var tenant by mutableStateOf<Tenant?>(null); private set
    var isTenantAdmin by mutableStateOf(false); private set
    var memberships by mutableStateOf<List<Member>>(emptyList()); private set
    /** Offene Admin-Aufgaben: Gruppen-Anträge (App-Admin) plus Beitrittsanfragen der eigenen Gruppen. */
    var adminPending by mutableStateOf(0); private set
    var error by mutableStateOf<String?>(null)
    private var started = false

    val signedIn get() = userId != null
    fun membership(communityId: String) = memberships.firstOrNull { it.communityId == communityId }
    val adminCommunityIds get() = memberships.filter { it.isAdmin }.map { it.communityId }
    val activeCommunityIds get() = memberships.filter { it.isActive }.map { it.communityId }
    val showsAdmin get() = isTenantAdmin || adminCommunityIds.isNotEmpty()

    fun start(scope: CoroutineScope) {
        if (started) return
        started = true
        scope.launch { runCatching { tenant = Tenants.current() } }
        scope.launch {
            Backend.supabase.auth.sessionStatus.collect { status ->
                when (status) {
                    is SessionStatus.Authenticated -> { userId = status.session.user?.id; refresh() }
                    is SessionStatus.NotAuthenticated -> { userId = null; profile = null; memberships = emptyList(); isTenantAdmin = false }
                    else -> {}
                }
            }
        }
    }

    /** Nach einem Gemeindewechsel: Mandant und Rollen neu. */
    suspend fun tenantChanged() {
        tenant = null
        isTenantAdmin = false
        runCatching { tenant = Tenants.current() }
        refresh()
    }

    suspend fun refresh() {
        val id = userId ?: return
        runCatching {
            if (tenant == null) tenant = Tenants.current()
            profile = CommunityApi.profile(id)
            memberships = CommunityApi.myMemberships(id)
            tenant?.let { isTenantAdmin = CommunityApi.isTenantAdmin(it.id) }
        }.onFailure { error = it.message }
        refreshAdminPending()
    }

    /** Zählt, was im Admin-Bereich wartet — steuert das gefüllte oder leere Siegel. */
    suspend fun refreshAdminPending() {
        if (!showsAdmin) { adminPending = 0; return }
        var count = runCatching { CommunityApi.pendingMemberCount(adminCommunityIds) }.getOrDefault(0)
        val t = tenant
        if (isTenantAdmin && t != null) count += runCatching { CommunityApi.pending(t.id).size }.getOrDefault(0)
        adminPending = count
    }

    suspend fun sendMagicLink(email: String): Boolean = runCatching {
        Backend.supabase.auth.signInWith(OTP, redirectUrl = "stede://auth-callback") { this.email = email }
    }.onFailure { error = it.message }.isSuccess

    /** Anmeldung mit Passwort — für Konten mit Passwort (Prüfkonten von Apple und Google). */
    suspend fun signIn(email: String, password: String): Boolean = runCatching {
        Backend.supabase.auth.signInWith(io.github.jan.supabase.auth.providers.builtin.Email) { this.email = email; this.password = password }
    }.onSuccess { error = null }.onFailure { error = "Anmeldung fehlgeschlagen. E-Mail oder Passwort stimmen nicht." }.isSuccess

    suspend fun setName(name: String) { val id = userId ?: return; runCatching { CommunityApi.setDisplayName(id, name); profile = CommunityApi.profile(id) }.onFailure { error = it.message } }
    /** Neues Profilbild (JPEG) setzen oder mit null entfernen; das alte Bild wird gelöscht. */
    suspend fun updateAvatar(jpeg: ByteArray?) {
        val id = userId ?: return
        val old = profile?.avatarUrl
        runCatching {
            val path = jpeg?.let { CommunityApi.uploadAvatar(id, it) }
            CommunityApi.setAvatar(id, path)
            if (old != null && !old.startsWith("http") && old != path) CommunityApi.deletePhoto("avatars", old)
            profile = CommunityApi.profile(id)
        }.onFailure { error = it.message }
    }
    suspend fun signOut() { runCatching { Backend.supabase.auth.signOut() } }
    suspend fun deleteAccount(): Boolean = runCatching { CommunityApi.deleteAccount() }.onFailure { error = it.message }.isSuccess
}
