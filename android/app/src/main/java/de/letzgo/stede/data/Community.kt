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

@Serializable data class Profile(@SerialName("user_id") val userId: String, @SerialName("display_name") val displayName: String = "Mitglied", @SerialName("avatar_url") val avatarUrl: String? = null) {
    /** Profilbild zum Anzeigen (Bucket `avatars`), null ohne Bild. */
    val avatar get() = Backend.avatarUrl(avatarUrl)
}

@Serializable data class Community(
    val id: String, @SerialName("tenant_id") val tenantId: String, val name: String, val description: String = "",
    val visibility: String = "listed", @SerialName("join_policy") val joinPolicy: String = "approval", val status: String = "pending",
    @SerialName("invite_code") val inviteCode: String? = null, @SerialName("logo_path") val logoPath: String? = null,
    @SerialName("created_by") val createdBy: String, @SerialName("member_count") val memberCount: Int? = null,
    /** Kreisweit: auch in den anderen Ammerland-Gemeinden gelistet. */
    val countywide: Boolean = false,
    /** Gruppen-Funktionen, in den Einstellungen schaltbar (fehlen in manchen Abfragen). */
    @SerialName("polls_enabled") val pollsEnabled: Boolean? = null,
    @SerialName("tasks_enabled") val tasksEnabled: Boolean? = null,
    /** Sonderfunktion der Veranstaltungs-Gruppe: Termine an andere Gruppen übertragen (nur im Backend freischaltbar). */
    @SerialName("can_transfer_events") val canTransferEvents: Boolean? = null,
) {
    val logoUrl get() = Backend.logoUrl(logoPath)
    val hasPolls get() = pollsEnabled ?: true
    val hasTasks get() = tasksEnabled ?: false
}

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
    /** Nur bei kreisweiten Gruppen: null = kreisweit, sonst nur diese Gemeinden (plus Heimatgemeinde). */
    @SerialName("target_tenants") val targetTenants: List<String>? = null,
    val visibility: String = "members", @SerialName("published_at") val publishedAt: String? = null,
    @SerialName("cancelled_at") val cancelledAt: String? = null, @SerialName("created_by") val createdBy: String? = null,
    @SerialName("communities") val community: CommunityRef? = null,
    /** Aus einem Gemeinde-Kalender übernommen (`<gemeinde>:<id>:<tag>`); null = in der App angelegt. */
    @SerialName("external_key") val externalKey: String? = null,
    /** Teilnahme abfragen (Zusagen, Helfer); übernommene Termine standardmäßig ohne. */
    @SerialName("rsvp_enabled") val rsvpEnabled: Boolean = true,
    @SerialName("all_day") val allDay: Boolean = false, val organizer: String? = null, val category: String? = null,
    @SerialName("source_url") val sourceUrl: String? = null, @SerialName("source_name") val sourceName: String? = null,
    @SerialName("image_credit") val imageCredit: String? = null, val price: String? = null, val registration: String? = null,
    @SerialName("sold_out") val soldOut: Boolean = false,
    /** Veranstalter eines übernommenen Termins (Tabelle `organizers`). */
    @SerialName("organizer_id") val organizerId: String? = null,
) {
    val isPublic get() = visibility == "public" && publishedAt != null
    val origin get() = EventOrigin(allDay, organizer, category, sourceUrl, sourceName, imageCredit, price, registration, soldOut)
}

@Serializable data class PublicEvent(
    val id: String, @SerialName("community_name") val communityName: String, @SerialName("community_logo_path") val communityLogoPath: String? = null,
    val title: String, val description: String = "", @SerialName("starts_at") val startsAt: String, @SerialName("ends_at") val endsAt: String? = null,
    val location: String? = null, @SerialName("image_path") val imagePath: String? = null, @SerialName("helpers_needed") val helpersNeeded: Int = 0,
    @SerialName("rsvp_enabled") val rsvpEnabled: Boolean = true,
    @SerialName("all_day") val allDay: Boolean = false, val organizer: String? = null, val category: String? = null,
    @SerialName("source_url") val sourceUrl: String? = null, @SerialName("source_name") val sourceName: String? = null,
    @SerialName("image_credit") val imageCredit: String? = null, val price: String? = null, val registration: String? = null,
    @SerialName("sold_out") val soldOut: Boolean = false,
) { val origin get() = EventOrigin(allDay, organizer, category, sourceUrl, sourceName, imageCredit, price, registration, soldOut) }

/** Ende eines Termins fürs Ausblenden und die Pille „vorbei“ (EventTiming in iOS). */
fun eventEnd(starts: ZonedDateTime, ends: ZonedDateTime?, allDay: Boolean): ZonedDateTime = when {
    ends != null && ends.isAfter(starts) -> ends
    allDay -> starts.withZoneSameInstant(Town.zone).toLocalDate().plusDays(1).atStartOfDay(Town.zone)
    else -> starts.plusHours(2)
}

/** Herkunft eines aus einem Gemeinde-Kalender übernommenen Termins (Gruppe „stede Veranstaltungen“):
 *  ganztägig, Veranstalter, Rubrik, Quelle mit Link und Foto-Credit. Bei Terminen aus der App leer. */
data class EventOrigin(
    val allDay: Boolean = false, val organizer: String? = null, val category: String? = null, val sourceUrl: String? = null,
    val sourceName: String? = null, val imageCredit: String? = null, val price: String? = null, val registration: String? = null,
    val soldOut: Boolean = false,
) {
    val isImported get() = sourceName != null
    /** Übernommene Termine zeigen ihren Veranstalter statt der Sammelgruppe. */
    val shownOrganizer get() = organizer?.takeIf { isImported && it.isNotBlank() }
}

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
    /** Gewählte Gemeinden eines öffentlichen Termins; null = kreisweit. */
    val targetTenants: List<String>? = null,
    val origin: EventOrigin = EventOrigin(),
    /** Aus: keine Zusage-Chips, keine Helfer, keine Zusagenliste. */
    val rsvpEnabled: Boolean = true,
    /** Veranstalter eines übernommenen Termins — für „Alle Termine von …“ übertragen. */
    val organizerId: String? = null,
) {
    val isImported get() = origin.isImported
    /** `community` ist der Veranstalter eines übernommenen Termins (statt „stede Veranstaltungen“ usw.). */
    val showsOrganizer get() = origin.shownOrganizer != null
    /** Vorbei wie EventTiming in iOS: mit Ende ab dem Ende, ganztägig ab Mitternacht danach, sonst zwei Stunden nach Beginn. */
    val isOver get() = !eventEnd(starts, ends, origin.allDay).isAfter(Town.now())
    companion object {
        fun of(e: CommunityEvent, fallbackName: String = "", fallbackLogo: String? = null) = EventInfo(
            e.id, e.title, e.origin.shownOrganizer ?: e.community?.name?.ifBlank { null } ?: fallbackName,
            if (e.origin.shownOrganizer != null) null else Backend.logoUrl(e.community?.logoPath) ?: fallbackLogo,
            Town.parse(e.startsAt)!!, Town.parse(e.endsAt), e.location, e.description, Backend.photoUrl(e.imagePath), e.isPublic, e.cancelledAt != null,
            e.helpersNeeded, e.createdBy, e.communityId, e.commentsEnabled, e.targetTenants, e.origin, e.rsvpEnabled, e.organizerId,
        )
        fun of(e: PublicEvent) = EventInfo(
            e.id, e.title, e.origin.shownOrganizer ?: e.communityName,
            if (e.origin.shownOrganizer != null) null else Backend.logoUrl(e.communityLogoPath), Town.parse(e.startsAt)!!, Town.parse(e.endsAt), e.location,
            e.description, Backend.photoUrl(e.imagePath), true, false, e.helpersNeeded, null, null, origin = e.origin, rsvpEnabled = e.rsvpEnabled,
        )
    }
}

@Serializable data class EventDraft(
    @SerialName("community_id") val communityId: String, val title: String, val description: String,
    @SerialName("starts_at") val startsAt: String, @SerialName("ends_at") val endsAt: String?, val location: String?,
    @SerialName("image_path") val imagePath: String?, @SerialName("helpers_needed") val helpersNeeded: Int,
    val visibility: String, @SerialName("created_by") val createdBy: String,
    /** Beide ohne Standardwert, damit sie immer mitgehen — Standardwerte lässt die Serialisierung weg,
     *  dann bliebe beim Bearbeiten „Kommentare an“ bzw. „Teilnahme aus“ stehen. */
    @SerialName("comments_enabled") val commentsEnabled: Boolean,
    @SerialName("rsvp_enabled") val rsvpEnabled: Boolean,
    /** Ohne Standardwert, damit das Feld immer (auch als null) mitgeht — sonst bliebe beim
     *  Bearbeiten eine alte Auswahl stehen, wenn der Termin wieder kreisweit wird. */
    @SerialName("target_tenants") val targetTenants: List<String>?,
)

/** Alle Zugriffe auf den Community-Teil; RLS entscheidet, was sichtbar ist. */
object CommunityApi {
    private val db get() = Backend.supabase
    private const val COMMUNITY = "id,tenant_id,name,description,visibility,join_policy,status,invite_code,logo_path,created_by,member_count,countywide,polls_enabled,tasks_enabled,can_transfer_events"
    private const val EVENT = "id,community_id,title,description,starts_at,ends_at,location,image_path,helpers_needed,comments_enabled,target_tenants,visibility,published_at,cancelled_at,created_by,external_key,rsvp_enabled,all_day,organizer,category,source_url,source_name,image_credit,price,registration,sold_out,organizer_id,communities(name,logo_path)"

    suspend fun isTenantAdmin(tenantId: String) = db.from("tenant_admins").select(Columns.raw("tenant_id")) { filter { eq("tenant_id", tenantId) } }.decodeList<Map<String, String>>().isNotEmpty()
    suspend fun profile(userId: String) = db.from("profiles").select { filter { eq("user_id", userId) } }.decodeSingle<Profile>()
    suspend fun setDisplayName(userId: String, name: String) { db.from("profiles").update({ set("display_name", name) }) { filter { eq("user_id", userId) } } }

    /** Gruppen der eigenen Gemeinde plus die kreisweiten aus dem ganzen Ammerland. */
    private fun io.github.jan.supabase.postgrest.query.filter.PostgrestFilterBuilder.ownOrCountywide(tenantId: String) {
        or { eq("tenant_id", tenantId); and { eq("countywide", true); eq("region", Brand.current.region) } }
    }

    /** Termine: eigene Gemeinde, sonst kreisweite Gruppen — sofern der Termin nicht auf andere Gemeinden beschränkt ist (`target_tenants`). */
    private fun io.github.jan.supabase.postgrest.query.filter.PostgrestFilterBuilder.ownOrTargeted(tenantId: String) {
        val id = tenantId.lowercase()
        // Gruppe nur für ihre Gemeinde · kreisweit ohne Auswahl · kreisweit mit dieser Gemeinde in der Auswahl
        // (auch die Heimatgemeinde muss dann gewählt sein).
        or {
            and { eq("countywide", false); eq("tenant_id", id) }
            and { eq("countywide", true); eq("region", Brand.current.region); exact("target_tenants", null) }
            and { eq("countywide", true); contains("target_tenants", listOf(id)) }
        }
    }

    suspend fun communities(tenantId: String) = db.from("v_community_overview").select(Columns.raw(COMMUNITY)) { filter { ownOrCountywide(tenantId) }; order("name", Order.ASCENDING) }.decodeList<Community>()
    suspend fun community(id: String) = db.from("v_community_overview").select(Columns.raw(COMMUNITY)) { filter { eq("id", id) } }.decodeSingle<Community>()
    suspend fun byInvite(code: String) = db.from("v_community_overview").select(Columns.raw(COMMUNITY)) { filter { eq("invite_code", code) }; limit(1) }.decodeList<Community>().firstOrNull()
    /** Offene Beitrittsanfragen in den Gruppen, die der Nutzer verwaltet. */
    suspend fun pendingMemberCount(communityIds: List<String>): Int {
        if (communityIds.isEmpty()) return 0
        return db.from("community_members").select(Columns.raw("user_id")) {
            filter { isIn("community_id", communityIds); eq("status", "pending") }
        }.decodeList<kotlinx.serialization.json.JsonObject>().size
    }

    suspend fun pending(tenantId: String) = db.from("v_community_overview").select(Columns.raw(COMMUNITY)) { filter { eq("tenant_id", tenantId); eq("status", "pending") } }.decodeList<Community>()

    suspend fun createCommunity(tenantId: String, name: String, description: String, visibility: String, joinPolicy: String, countywide: Boolean, userId: String): Community =
        db.from("communities").insert(buildJsonObject {
            put("tenant_id", tenantId); put("name", name); put("description", description); put("visibility", visibility); put("join_policy", joinPolicy)
            put("countywide", countywide); put("created_by", userId)
        }) { select(Columns.raw("id,tenant_id,name,description,visibility,join_policy,status,invite_code,logo_path,created_by,countywide")) }.decodeSingle()

    suspend fun updateCommunity(id: String, name: String, description: String, visibility: String, joinPolicy: String, countywide: Boolean, logoPath: String?) {
        db.from("communities").update(buildJsonObject {
            put("name", name); put("description", description); put("visibility", visibility); put("join_policy", joinPolicy); put("countywide", countywide); put("logo_path", logoPath)
        }) { filter { eq("id", id) } }
    }
    /** Umfragen und Aufgaben der Gruppe ein- oder ausschalten (Admins/Leitung). */
    suspend fun setFeatures(id: String, polls: Boolean, tasks: Boolean) {
        db.from("communities").update(buildJsonObject { put("polls_enabled", polls); put("tasks_enabled", tasks) }) { filter { eq("id", id) } }
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
    suspend fun publicEvents(tenantId: String, fromIso: String, toIso: String) = db.from("v_public_events").select(Columns.raw("id,community_name,community_logo_path,title,description,starts_at,ends_at,location,image_path,helpers_needed,rsvp_enabled,all_day,organizer,category,source_url,source_name,image_credit,price,registration")) {
        filter { ownOrTargeted(tenantId); gte("starts_at", fromIso); lt("starts_at", toIso) }; order("starts_at", Order.ASCENDING)
    }.decodeList<PublicEvent>()

    suspend fun createEvent(d: EventDraft) { db.from("community_events").insert(d) }
    suspend fun updateEvent(id: String, d: EventDraft) { db.from("community_events").update(d) { filter { eq("id", id) } } }
    /** Kommentare eines internen Termins ein- oder ausschalten (Schnellmenü der Karte). */
    suspend fun setEventComments(id: String, enabled: Boolean) { db.from("community_events").update({ set("comments_enabled", enabled) }) { filter { eq("id", id) } } }
    /** Termin der Veranstaltungs-Gruppe an eine andere Gruppe übertragen; `series` nimmt alle künftigen Termine gleichen
     *  Titels mit und leitet neue Importe dieser Reihe gleich dorthin. Liefert die Zahl der Termine. */
    suspend fun transferEvents(eventId: String, target: String, series: Boolean): Int =
        db.postgrest.rpc("transfer_events", buildJsonObject { put("p_event", eventId); put("p_target", target); put("p_series", series) }).decodeAs<Int>()
    /** Verknüpft den Veranstalter des Termins mit der Zielgruppe: alle künftigen Termine dieses Veranstalters
     *  wandern dorthin, neue Importe landen direkt dort. Liefert die Zahl der verschobenen Termine. */
    suspend fun transferOrganizer(eventId: String, target: String): Int =
        db.postgrest.rpc("transfer_organizer", buildJsonObject { put("p_event", eventId); put("p_target", target) }).decodeAs<Int>()
    suspend fun cancelEvent(id: String) { db.from("community_events").update({ set("cancelled_at", java.time.Instant.now().toString()) }) { filter { eq("id", id) } } }

    suspend fun comments(eventId: String) = db.from("event_comments").select(Columns.raw("id,event_id,user_id,body,created_at,profiles(user_id,display_name,avatar_url)")) {
        filter { eq("event_id", eventId) }; order("created_at", io.github.jan.supabase.postgrest.query.Order.ASCENDING)
    }.decodeList<EventComment>()
    suspend fun addComment(eventId: String, userId: String, body: String) {
        db.from("event_comments").insert(buildJsonObject { put("event_id", eventId); put("user_id", userId); put("body", body) })
    }
    suspend fun deleteComment(id: String) { db.from("event_comments").delete { filter { eq("id", id) } } }
    @Serializable private data class CommentRow(@SerialName("event_id") val eventId: String)
    /** Anzahl Kommentare je Termin — für den Knopf unter der Karte. */
    suspend fun commentCounts(eventIds: List<String>): Map<String, Int> {
        if (eventIds.isEmpty()) return emptyMap()
        return db.from("event_comments").select(Columns.raw("event_id")) { filter { isIn("event_id", eventIds) } }
            .decodeList<CommentRow>().groupingBy { it.eventId }.eachCount()
    }

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
