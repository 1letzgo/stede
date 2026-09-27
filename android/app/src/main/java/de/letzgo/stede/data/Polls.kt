package de.letzgo.stede.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.ZonedDateTime

/** Umfrage einer Gruppe (`community_polls`) — nur für aktive Mitglieder sichtbar; wie CommunityPoll in iOS. */
@Serializable data class CommunityPoll(
    val id: String, @SerialName("community_id") val communityId: String, val question: String, val description: String? = null,
    /** „text“ (freie Antworten) oder „date“ (Terminfindung). */
    val kind: String = "text",
    /** Mehrere Antworten erlaubt; sonst ersetzt eine neue Stimme die alte (Trigger in der DB). */
    val multiple: Boolean = false,
    @SerialName("closes_at") val closesAt: String? = null, @SerialName("closed_at") val closedAt: String? = null,
    /** Kommentare der Mitglieder unter der Umfrage (wie bei internen Terminen). */
    @SerialName("comments_enabled") val commentsEnabled: Boolean = false,
    @SerialName("created_by") val createdBy: String? = null, @SerialName("created_at") val createdAt: String? = null,
    @SerialName("community_poll_options") val rawOptions: List<PollOption> = emptyList(),
) {
    val isDate get() = kind == "date"
    val options get() = rawOptions.sortedBy { it.sortOrder }
    val closes get() = Town.parse(closesAt)
    /** Offen, solange nicht beendet und das Enddatum nicht erreicht ist. */
    fun isOpen(now: ZonedDateTime = Town.now()) = closedAt == null && (closes?.isAfter(now) ?: true)
}

/** Eine Antwortmöglichkeit; bei Terminfindung trägt sie den Zeitpunkt. */
@Serializable data class PollOption(
    val id: String, val label: String = "", @SerialName("starts_at") val startsAt: String? = null, @SerialName("sort_order") val sortOrder: Int = 0,
)

/** Eine Stimme mit Namen (alle Mitglieder sehen, wer was gewählt hat). */
@Serializable data class PollVote(
    @SerialName("poll_id") val pollId: String, @SerialName("option_id") val optionId: String, @SerialName("user_id") val userId: String,
    @SerialName("profiles") val profile: Profile? = null,
)

/** Eingabe für eine neue Umfrage; Möglichkeiten als Text oder Zeitpunkt, in Reihenfolge. */
data class PollDraft(
    val question: String, val description: String, val kind: String, val multiple: Boolean, val closesAt: ZonedDateTime?,
    val options: List<Pair<String, ZonedDateTime?>>, val commentsEnabled: Boolean = false,
)

/** Umfragen — Tabellen `community_polls`, `community_poll_options`, `community_poll_votes`. RLS: lesen und abstimmen
 *  nur aktive Mitglieder (abstimmen nur, solange offen), anlegen, beenden und löschen nur Admins/Leitung. */
object PollApi {
    private val db get() = Backend.supabase
    private const val POLL = "id,community_id,question,description,kind,multiple,closes_at,closed_at,comments_enabled,created_by,created_at,community_poll_options(id,label,starts_at,sort_order)"

    /** Neueste zuerst. */
    suspend fun polls(communityId: String) = db.from("community_polls").select(Columns.raw(POLL)) {
        filter { eq("community_id", communityId) }; order("created_at", Order.DESCENDING); limit(100)
    }.decodeList<CommunityPoll>()

    suspend fun votes(pollIds: List<String>): List<PollVote> {
        if (pollIds.isEmpty()) return emptyList()
        return db.from("community_poll_votes").select(Columns.raw("poll_id,option_id,user_id,profiles(user_id,display_name,avatar_url)")) {
            filter { isIn("poll_id", pollIds) }
        }.decodeList()
    }

    @Serializable private data class Created(val id: String)

    suspend fun create(draft: PollDraft, communityId: String, userId: String) {
        val poll = db.from("community_polls").insert(buildJsonObject {
            put("community_id", communityId); put("question", draft.question); put("description", draft.description); put("kind", draft.kind)
            put("multiple", draft.multiple); put("closes_at", draft.closesAt?.toOffsetDateTime()?.toString())
            put("comments_enabled", draft.commentsEnabled); put("created_by", userId)
        }) { select(Columns.raw("id")) }.decodeSingle<Created>()
        val rows = buildJsonArray {
            draft.options.forEachIndexed { index, (label, startsAt) ->
                add(buildJsonObject {
                    put("poll_id", poll.id); put("label", label); put("starts_at", startsAt?.toOffsetDateTime()?.toString()); put("sort_order", index)
                })
            }
        }
        try {
            db.from("community_poll_options").insert(rows)
        } catch (e: Exception) {
            // Ohne Antworten ist die Umfrage wertlos — wieder weg damit.
            runCatching { delete(poll.id) }
            throw e
        }
    }

    suspend fun vote(pollId: String, optionId: String, userId: String) {
        db.from("community_poll_votes").insert(buildJsonObject { put("poll_id", pollId); put("option_id", optionId); put("user_id", userId) })
    }

    suspend fun unvote(optionId: String, userId: String) {
        db.from("community_poll_votes").delete { filter { eq("option_id", optionId); eq("user_id", userId) } }
    }

    suspend fun close(pollId: String) {
        db.from("community_polls").update(buildJsonObject { put("closed_at", java.time.Instant.now().toString()) }) { filter { eq("id", pollId) } }
    }

    suspend fun setComments(pollId: String, enabled: Boolean) {
        db.from("community_polls").update(buildJsonObject { put("comments_enabled", enabled) }) { filter { eq("id", pollId) } }
    }

    // Kommentare (`poll_comments`) — gleiche Form wie EventComment, `event_id` ist hier die Umfrage.

    suspend fun comments(pollId: String) = db.from("poll_comments").select(Columns.raw("id,event_id:poll_id,user_id,body,created_at,profiles(user_id,display_name,avatar_url)")) {
        filter { eq("poll_id", pollId) }; order("created_at", Order.ASCENDING)
    }.decodeList<EventComment>()

    suspend fun addComment(pollId: String, userId: String, body: String) {
        db.from("poll_comments").insert(buildJsonObject { put("poll_id", pollId); put("user_id", userId); put("body", body) })
    }

    suspend fun deleteComment(id: String) { db.from("poll_comments").delete { filter { eq("id", id) } } }

    @Serializable private data class CommentRow(@SerialName("poll_id") val pollId: String)

    /** Anzahl Kommentare je Umfrage — für den Knopf unter der Karte. */
    suspend fun commentCounts(pollIds: List<String>): Map<String, Int> {
        if (pollIds.isEmpty()) return emptyMap()
        return db.from("poll_comments").select(Columns.raw("poll_id")) { filter { isIn("poll_id", pollIds) } }
            .decodeList<CommentRow>().groupingBy { it.pollId }.eachCount()
    }

    suspend fun delete(pollId: String) { db.from("community_polls").delete { filter { eq("id", pollId) } } }
}
