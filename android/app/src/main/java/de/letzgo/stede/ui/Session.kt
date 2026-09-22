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

    suspend fun refresh() {
        val id = userId ?: return
        runCatching {
            if (tenant == null) tenant = Tenants.current()
            profile = CommunityApi.profile(id)
            memberships = CommunityApi.myMemberships(id)
            tenant?.let { isTenantAdmin = CommunityApi.isTenantAdmin(it.id) }
        }.onFailure { error = it.message }
    }

    suspend fun sendMagicLink(email: String): Boolean = runCatching {
        Backend.supabase.auth.signInWith(OTP, redirectUrl = "stede://auth-callback") { this.email = email }
    }.onFailure { error = it.message }.isSuccess

    suspend fun setName(name: String) { val id = userId ?: return; runCatching { CommunityApi.setDisplayName(id, name); profile = CommunityApi.profile(id) }.onFailure { error = it.message } }
    suspend fun signOut() { runCatching { Backend.supabase.auth.signOut() } }
    suspend fun deleteAccount(): Boolean = runCatching { CommunityApi.deleteAccount() }.onFailure { error = it.message }.isSuccess
}
