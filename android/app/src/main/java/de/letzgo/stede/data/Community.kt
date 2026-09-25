package de.letzgo.stede.data

import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import io.ktor.http.ContentType
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.add
import java.time.ZonedDateTime
import java.util.UUID

@Serializable data class Tenant(val id: String, val slug: String, val name: String, val municipality: String)

object Tenants {
    private var cached: Tenant? = null
    suspend fun current(): Tenant = cached ?: Backend.supabase.from("tenants").select(Columns.raw("id,slug,name,municipality")) {
        filter { eq("slug", Backend.TENANT) }
    }.decodeSingle<Tenant>().also { cached = it }
}

@Serializable data class Profile(@SerialName("user_id") val userId: String, @SerialName("display_name") val displayName: String = "Mitglied", @SerialName("avatar_url") val avatarUrl: String? = null) {
    /** Profilbild zum Anzeigen (Bucket `avatars`), null ohne Bild. */
    val avatar get() = Backend.avatarUrl(avatarUrl)
}

@Serializable data class Community(
    val id: String, @SerialName("tenant_id") val tenantId: String, val name: String, val description: String = "",
    val visibility: String = "listed", @SerialName("join_policy") val joinPolicy: String = "approval", val status: String = "pending",
    @SerialName("invite_code") val inviteCode: String? = null, @SerialName("logo_path") val logoPath: String? = null,
    @SerialName("created_by") val createdBy: String, @SerialName("member_count") val memberCount: Int? = null,
) { val logoUrl get() = Backend.logoUrl(logoPath) }

@Serializable data class Member(
    @SerialName("community_id") val communityId: String, @SerialName("user_id") val userId: String,
    val role: String = "member", val status: String = "pending", @SerialName("profiles") val profile: Profile? = null,
    /** Kurze Vorstellung aus dem Beitrittsantrag; nach der Freischaltung leer. */
    @SerialName("join_message") val joinMessage: String? = null,
) { val id get() = "$communityId|$userId"; val isActive get() = status == "active"; val isAdmin get() = isActive && (role == "owner" || role == "admin") }

@Serializable data class CommunityRef(val name: String = "", @SerialName("logo_path") val logoPath: String? = null)

@Serializable data class CommunityEvent(
    val id: String, @SerialName("community_id") val communityId: String, val title: String, val description: String = "",
    @SerialName("starts_at") val startsAt: String, @SerialName("ends_at") val endsAt: String? = null, val location: String? = null,
    @SerialName("image_path") val imagePath: String? = null, @SerialName("helpers_needed") val helpersNeeded: Int = 0,
    @SerialName("comments_enabled") val commentsEnabled: Boolean = false,
    val visibility: String = "members", @SerialName("published_at") val publishedAt: String? = null,
    @SerialName("cancelled_at") val cancelledAt: String? = null, @SerialName("created_by") val createdBy: String? = null,
    @SerialName("communities") val community: CommunityRef? = null,
) { val isPublic get() = visibility == "public" && publishedAt != null }

@Serializable data class PublicEvent(
    val id: String, @SerialName("community_name") val communityName: String, @SerialName("community_logo_path") val communityLogoPath: String? = null,
    val title: String, val description: String = "", @SerialName("starts_at") val startsAt: String, @SerialName("ends_at") val endsAt: String? = null,
    val location: String? = null, @SerialName("image_path") val imagePath: String? = null, @SerialName("helpers_needed") val helpersNeeded: Int = 0,
)

/** Standardbild einer Community — als Termin-Kopfbild wählbar; liegt in event-photos/<community>/defaults/. */
@Serializable data class HeaderImage(
    val id: String, @SerialName("community_id") val communityId: String, val path: String,
    val label: String = "", @SerialName("sort_order") val sortOrder: Int = 0,
) {
    val url get() = Backend.photoUrl(path)!!
    companion object { fun isDefault(path: String) = path.contains("/defaults/") }
}

@Serializable data class Participation(
    @SerialName("event_id") val eventId: String, @SerialName("user_id") val userId: String, val status: String, val helping: Boolean = false,
    @SerialName("profiles") val profile: Profile? = null,
)

/** Kommentar zu einem internen Gruppen-Termin (`event_comments`). */
@Serializable data class EventComment(
    val id: String, @SerialName("event_id") val eventId: String, @SerialName("user_id") val userId: String, val body: String,
    @SerialName("created_at") val createdAt: String, @SerialName("profiles") val profile: Profile? = null,
)

/** Was Karte und Detail über einen Community-Termin brauchen — aus beiden Quellen gebaut. */
data class EventInfo(
    val id: String, val title: String, val community: String, val logoUrl: String?, val starts: ZonedDateTime, val ends: ZonedDateTime?,
    val location: String?, val description: String, val imageUrl: String?, val isPublic: Boolean, val isCancelled: Boolean,
    val helpersNeeded: Int, val createdBy: String?, val communityId: String?,
    /** Kommentare eingeschaltet — nur bei internen Terminen. */
    val commentsEnabled: Boolean = false,
) {
    companion object {
        fun of(e: CommunityEvent, fallbackName: String = "", fallbackLogo: String? = null) = EventInfo(
            e.id, e.title, e.community?.name?.ifBlank { null } ?: fallbackName, Backend.logoUrl(e.community?.logoPath) ?: fallbackLogo,
            Town.parse(e.startsAt)!!, Town.parse(e.endsAt), e.location, e.description, Backend.photoUrl(e.imagePath), e.isPublic, e.cancelledAt != null,
            e.helpersNeeded, e.createdBy, e.communityId, e.commentsEnabled && !e.isPublic,
        )
        fun of(e: PublicEvent) = EventInfo(
            e.id, e.title, e.communityName, Backend.logoUrl(e.communityLogoPath), Town.parse(e.startsAt)!!, Town.parse(e.endsAt), e.location,
            e.description, Backend.photoUrl(e.imagePath), true, false, e.helpersNeeded, null, null,
        )
    }
}

@Serializable data class EventDraft(
    @SerialName("community_id") val communityId: String, val title: String, val description: String,
    @SerialName("starts_at") val startsAt: String, @SerialName("ends_at") val endsAt: String?, val location: String?,
    @SerialName("image_path") val imagePath: String?, @SerialName("helpers_needed") val helpersNeeded: Int,
    val visibility: String, @SerialName("created_by") val createdBy: String,
    @SerialName("comments_enabled") val commentsEnabled: Boolean = false,
)

/** Alle Zugriffe auf den Community-Teil; RLS entscheidet, was sichtbar ist. */
object CommunityApi {
    private val db get() = Backend.supabase
    private const val COMMUNITY = "id,tenant_id,name,description,visibility,join_policy,status,invite_code,logo_path,created_by,member_count"
    private const val EVENT = "id,community_id,title,description,starts_at,ends_at,location,image_path,helpers_needed,comments_enabled,visibility,published_at,cancelled_at,created_by,communities(name,logo_path)"

    suspend fun isTenantAdmin(tenantId: String) = db.from("tenant_admins").select(Columns.raw("tenant_id")) { filter { eq("tenant_id", tenantId) } }.decodeList<Map<String, String>>().isNotEmpty()
    suspend fun profile(userId: String) = db.from("profiles").select { filter { eq("user_id", userId) } }.decodeSingle<Profile>()
    suspend fun setDisplayName(userId: String, name: String) { db.from("profiles").update({ set("display_name", name) }) { filter { eq("user_id", userId) } } }

    suspend fun communities(tenantId: String) = db.from("v_community_overview").select(Columns.raw(COMMUNITY)) { filter { eq("tenant_id", tenantId) }; order("name", Order.ASCENDING) }.decodeList<Community>()
    suspend fun community(id: String) = db.from("v_community_overview").select(Columns.raw(COMMUNITY)) { filter { eq("id", id) } }.decodeSingle<Community>()
    suspend fun byInvite(code: String) = db.from("v_community_overview").select(Columns.raw(COMMUNITY)) { filter { eq("invite_code", code) }; limit(1) }.decodeList<Community>().firstOrNull()
    suspend fun pending(tenantId: String) = db.from("v_community_overview").select(Columns.raw(COMMUNITY)) { filter { eq("tenant_id", tenantId); eq("status", "pending") } }.decodeList<Community>()

    suspend fun createCommunity(tenantId: String, name: String, description: String, visibility: String, joinPolicy: String, userId: String): Community =
        db.from("communities").insert(buildJsonObject {
            put("tenant_id", tenantId); put("name", name); put("description", description); put("visibility", visibility); put("join_policy", joinPolicy); put("created_by", userId)
        }) { select(Columns.raw("id,tenant_id,name,description,visibility,join_policy,status,invite_code,logo_path,created_by")) }.decodeSingle()

    suspend fun updateCommunity(id: String, name: String, description: String, visibility: String, joinPolicy: String, logoPath: String?) {
        db.from("communities").update(buildJsonObject { put("name", name); put("description", description); put("visibility", visibility); put("join_policy", joinPolicy); put("logo_path", logoPath) }) { filter { eq("id", id) } }
    }
    suspend fun setCommunityStatus(id: String, status: String) { db.from("communities").update({ set("status", status) }) { filter { eq("id", id) } } }

    suspend fun myMemberships(userId: String) = db.from("community_members").select(Columns.raw("community_id,user_id,role,status")) { filter { eq("user_id", userId) } }.decodeList<Member>()
    suspend fun members(communityId: String) = db.from("community_members").select(Columns.raw("community_id,user_id,role,status,join_message,profiles(user_id,display_name,avatar_url)")) { filter { eq("community_id", communityId) } }.decodeList<Member>()
    /** Beitritt bzw. Antrag; `message` ist die optionale Kurzvorstellung für die Admins. */
    suspend fun join(communityId: String, userId: String, message: String? = null) {
        db.from("community_members").insert(buildJsonObject {
            put("community_id", communityId); put("user_id", userId)
            message?.trim()?.takeIf { it.isNotEmpty() }?.let { put("join_message", it.take(500)) }
        })
    }
    suspend fun removeMember(communityId: String, userId: String) { db.from("community_members").delete { filter { eq("community_id", communityId); eq("user_id", userId) } } }
    suspend fun setMemberStatus(communityId: String, userId: String, status: String) { db.from("community_members").update({ set("status", status) }) { filter { eq("community_id", communityId); eq("user_id", userId) } } }
    suspend fun setMemberRole(communityId: String, userId: String, role: String) { db.from("community_members").update({ set("role", role) }) { filter { eq("community_id", communityId); eq("user_id", userId) } } }

    suspend fun events(communityId: String, fromIso: String) = db.from("community_events").select(Columns.raw(EVENT)) { filter { eq("community_id", communityId); gte("starts_at", fromIso) }; order("starts_at", Order.ASCENDING) }.decodeList<CommunityEvent>()
    /** Vergangene Termine einer Community, neueste zuerst. */
    suspend fun pastEvents(communityId: String, beforeIso: String, offset: Long = 0, limit: Long = 20) = db.from("community_events").select(Columns.raw(EVENT)) {
        filter { eq("community_id", communityId); lt("starts_at", beforeIso) }; order("starts_at", Order.DESCENDING); range(offset, offset + limit - 1)
    }.decodeList<CommunityEvent>()
    suspend fun events(communityIds: List<String>, fromIso: String, toIso: String): List<CommunityEvent> {
        if (communityIds.isEmpty()) return emptyList()
        return db.from("community_events").select(Columns.raw(EVENT)) { filter { isIn("community_id", communityIds); gte("starts_at", fromIso); lt("starts_at", toIso) }; order("starts_at", Order.ASCENDING) }.decodeList()
    }
    suspend fun publicEvents(tenantId: String, fromIso: String, toIso: String) = db.from("v_public_events").select(Columns.raw("id,community_name,community_logo_path,title,description,starts_at,ends_at,location,image_path,helpers_needed")) {
        filter { eq("tenant_id", tenantId); gte("starts_at", fromIso); lt("starts_at", toIso) }; order("starts_at", Order.ASCENDING)
    }.decodeList<PublicEvent>()

    suspend fun createEvent(d: EventDraft) { db.from("community_events").insert(d) }
    suspend fun updateEvent(id: String, d: EventDraft) { db.from("community_events").update(d) { filter { eq("id", id) } } }
    suspend fun cancelEvent(id: String) { db.from("community_events").update({ set("cancelled_at", java.time.Instant.now().toString()) }) { filter { eq("id", id) } } }

    suspend fun comments(eventId: String) = db.from("event_comments").select(Columns.raw("id,event_id,user_id,body,created_at,profiles(user_id,display_name,avatar_url)")) {
        filter { eq("event_id", eventId) }; order("created_at", io.github.jan.supabase.postgrest.query.Order.ASCENDING)
    }.decodeList<EventComment>()
    suspend fun addComment(eventId: String, userId: String, body: String) {
        db.from("event_comments").insert(buildJsonObject { put("event_id", eventId); put("user_id", userId); put("body", body) })
    }
    suspend fun deleteComment(id: String) { db.from("event_comments").delete { filter { eq("id", id) } } }

    suspend fun myParticipations(userId: String) = db.from("event_participations").select(Columns.raw("event_id,user_id,status,helping")) { filter { eq("user_id", userId) } }.decodeList<Participation>()
    suspend fun participations(eventId: String) = db.from("event_participations").select(Columns.raw("event_id,user_id,status,helping,profiles(user_id,display_name,avatar_url)")) { filter { eq("event_id", eventId) } }.decodeList<Participation>()
    suspend fun setParticipation(eventId: String, userId: String, status: String?, helping: Boolean) {
        if (status == null) db.from("event_participations").delete { filter { eq("event_id", eventId); eq("user_id", userId) } }
        else db.from("event_participations").upsert(buildJsonObject { put("event_id", eventId); put("user_id", userId); put("status", status); put("helping", helping && status != "declined") })
    }
    @Serializable private data class HelperCount(@SerialName("event_id") val eventId: String, val helpers: Int)
    suspend fun helperCounts(ids: List<String>): Map<String, Int> {
        if (ids.isEmpty()) return emptyMap()
        return db.postgrest.rpc("event_helper_counts", buildJsonObject { putJsonArray("event_ids") { ids.forEach { add(it) } } }).decodeList<HelperCount>().associate { it.eventId to it.helpers }
    }

    suspend fun uploadPhoto(bucket: String, communityId: String, jpeg: ByteArray): String {
        val path = "${communityId.lowercase()}/${UUID.randomUUID().toString().lowercase()}.jpg"
        db.storage.from(bucket).upload(path, jpeg) { upsert = false; contentType = ContentType.Image.JPEG }
        return path
    }
    /** Profilbild hochladen; der Ordner ist die eigene User-ID (RLS). */
    suspend fun uploadAvatar(userId: String, jpeg: ByteArray): String {
        val path = "${userId.lowercase()}/${UUID.randomUUID().toString().lowercase()}.jpg"
        db.storage.from("avatars").upload(path, jpeg) { upsert = false; contentType = ContentType.Image.JPEG }
        return path
    }
    suspend fun setAvatar(userId: String, path: String?) {
        db.from("profiles").update(buildJsonObject { put("avatar_url", path) }) { filter { eq("user_id", userId) } }
    }
    suspend fun deletePhoto(bucket: String, path: String) {
        if (bucket == "event-photos" && HeaderImage.isDefault(path)) return // Standardbilder nie mit einem Termin löschen
        runCatching { db.storage.from(bucket).delete(path) }
    }

    suspend fun headerImages(communityId: String) = db.from("community_header_images").select(Columns.raw("id,community_id,path,label,sort_order")) {
        filter { eq("community_id", communityId) }; order("sort_order", Order.ASCENDING); order("created_at", Order.ASCENDING)
    }.decodeList<HeaderImage>()

    suspend fun addHeaderImage(jpeg: ByteArray, label: String, communityId: String, userId: String, sortOrder: Int) {
        val path = "${communityId.lowercase()}/defaults/${UUID.randomUUID().toString().lowercase()}.jpg"
        db.storage.from("event-photos").upload(path, jpeg) { upsert = false; contentType = ContentType.Image.JPEG }
        db.from("community_header_images").insert(buildJsonObject {
            put("community_id", communityId); put("path", path); put("label", label); put("sort_order", sortOrder); put("created_by", userId)
        })
    }

    /** Entfernt Eintrag und Datei; Termine, die das Bild nutzen, verlieren ihr Kopfbild. */
    suspend fun deleteHeaderImage(image: HeaderImage) {
        db.from("community_header_images").delete { filter { eq("id", image.id) } }
        runCatching { db.from("community_events").update(buildJsonObject { put("image_path", null as String?) }) { filter { eq("community_id", image.communityId); eq("image_path", image.path) } } }
        runCatching { db.storage.from("event-photos").delete(image.path) }
    }

    @Serializable private data class TokenRow(val token: String)
    suspend fun calendarToken(userId: String): String {
        db.from("calendar_tokens").select(Columns.raw("token")) { filter { eq("user_id", userId); exact("revoked_at", null) } }.decodeList<TokenRow>().firstOrNull()?.let { return it.token }
        return db.from("calendar_tokens").upsert(buildJsonObject { put("user_id", userId) }) { select(Columns.raw("token")) }.decodeSingle<TokenRow>().token
    }

    suspend fun deleteAccount() { db.functions.invoke("delete-account"); db.auth.signOut() }
}
