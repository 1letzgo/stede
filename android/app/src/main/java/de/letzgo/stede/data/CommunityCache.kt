package de.letzgo.stede.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString

/** Letzter Stand der Gruppen-Bereiche wie CommunityCache in iOS: Gruppenliste, Konto (Profil, Mitgliedschaften),
 *  „Meine Aufgaben“, Gruppenseiten. Zuerst zeigen, im Hintergrund nachladen, bei Fehlern stehen lassen.
 *  Abgelegt je Gemeinde und Nutzer in `filesDir/community/…/<nutzer>/<name>.json` (ohne Anmeldung `anon`). */
object CommunityCache {
    fun folder(userId: String?) = "${Tenants.folder("community")}/${userId?.lowercase() ?: "anon"}"

    inline fun <reified T> read(name: String, userId: String?): T? =
        Store.read(folder(userId), "$name.json")?.let { runCatching { Http.json.decodeFromString<T>(it) }.getOrNull() }

    inline fun <reified T> write(name: String, userId: String?, value: T) {
        runCatching { Store.write(folder(userId), "$name.json", Http.json.encodeToString(value)) }
    }

    /** Nach dem Abmelden: nichts von Konten auf dem Gerät lassen. */
    fun clear() { runCatching { Store.file("community", ".keep").parentFile?.deleteRecursively() } }
}

/** Konto-Stand für den Cache. */
@Serializable data class AccountSnapshot(val profile: Profile? = null, val memberships: List<Member> = emptyList(), val isTenantAdmin: Boolean = false)

/** Stand einer Gruppenseite für den Cache. */
@Serializable data class GroupSnapshot(val community: Community, val members: List<Member> = emptyList(), val events: List<CommunityEvent> = emptyList())
