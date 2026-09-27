package de.letzgo.stede.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.LocalDate

/** Projekt einer Gruppe (`community_projects`) — sammelt Aufgaben; nur Admins/Leitung legen an. Wie CommunityProject in iOS. */
@Serializable data class CommunityProject(
    val id: String, @SerialName("community_id") val communityId: String, val title: String,
    @SerialName("description") val rawDescription: String? = null,
    @SerialName("created_by") val createdBy: String? = null, @SerialName("created_at") val createdAt: String? = null,
    @SerialName("archived_at") val archivedAt: String? = null,
) {
    val description get() = rawDescription.orEmpty()
    val isArchived get() = archivedAt != null
}

/** Status einer Aufgabe; `raw` ist der Wert in der Datenbank. */
enum class TaskStatus(val raw: String, val title: String) {
    Open("open", "Offen"), InProgress("in_progress", "In Arbeit"), Done("done", "Erledigt");
    companion object { fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Open }
}

/** Zuständige Person einer Aufgabe (`community_task_assignees`) samt Profil. */
@Serializable data class TaskAssignee(@SerialName("user_id") val userId: String, @SerialName("profiles") val profile: Profile? = null)

/** Aufgabe in einem Projekt (`community_tasks`) mit Zuständigen — wie CommunityTask in iOS. */
@Serializable data class CommunityTask(
    val id: String, @SerialName("project_id") val projectId: String, @SerialName("community_id") val communityId: String,
    val title: String, @SerialName("description") val rawDescription: String? = null,
    @SerialName("status") val rawStatus: String? = null,
    /** Nur Datum (`YYYY-MM-DD`), ohne Uhrzeit. */
    @SerialName("due_date") val dueDate: String? = null,
    @SerialName("created_by") val createdBy: String? = null, @SerialName("created_at") val createdAt: String? = null,
    @SerialName("done_at") val doneAt: String? = null,
    @SerialName("community_task_assignees") val assignees: List<TaskAssignee> = emptyList(),
) {
    val description get() = rawDescription.orEmpty()
    val status get() = TaskStatus.of(rawStatus)
    /** Fälligkeitstag (Ortszeit). */
    val due: LocalDate? get() = dueDate?.let { runCatching { LocalDate.parse(it.take(10)) }.getOrNull() }
    fun isAssigned(userId: String?) = userId != null && assignees.any { it.userId.equals(userId, ignoreCase = true) }
    /** Überfällig: Fälligkeitstag vorbei und noch nicht erledigt. */
    fun isOverdue(today: LocalDate = Town.today()) = status != TaskStatus.Done && due?.isBefore(today) == true
}

/** Eingabe für eine neue oder geänderte Aufgabe. */
data class TaskDraft(val title: String, val description: String, val status: TaskStatus, val due: LocalDate?, val assignees: List<String>)

/** Projekte und Aufgaben einer Gruppe — Tabellen `community_projects`, `community_tasks`, `community_task_assignees`,
 *  `task_comments`. RLS: lesen aktive Mitglieder; Projekte verwalten Admins/Leitung; Aufgaben legt jedes Mitglied an;
 *  ändern Admins, Ersteller und Zuständige; zuweisen Admins und Ersteller, selbst übernehmen jedes Mitglied. */
object TaskApi {
    private val db get() = Backend.supabase
    private const val PROJECT = "id,community_id,title,description,created_by,created_at,archived_at"
    private const val TASK = "id,project_id,community_id,title,description,status,due_date,created_by,created_at,done_at,community_task_assignees(user_id,profiles(user_id,display_name,avatar_url))"

    // Projekte

    suspend fun projects(communityId: String) = db.from("community_projects").select(Columns.raw(PROJECT)) {
        filter { eq("community_id", communityId) }; order("created_at", Order.DESCENDING)
    }.decodeList<CommunityProject>()

    suspend fun createProject(communityId: String, title: String, description: String, userId: String) {
        db.from("community_projects").insert(buildJsonObject {
            put("community_id", communityId); put("title", title); put("description", description); put("created_by", userId)
        })
    }

    suspend fun updateProject(id: String, title: String, description: String) {
        db.from("community_projects").update(buildJsonObject { put("title", title); put("description", description) }) { filter { eq("id", id) } }
    }

    suspend fun setProjectArchived(id: String, archived: Boolean) {
        db.from("community_projects").update(buildJsonObject { put("archived_at", if (archived) java.time.Instant.now().toString() else null) }) { filter { eq("id", id) } }
    }

    suspend fun deleteProject(id: String) { db.from("community_projects").delete { filter { eq("id", id) } } }

    // Aufgaben

    /** Alle Aufgaben der Gruppe (für Zähler auf den Projektkarten und die Projektansicht). */
    suspend fun tasks(communityId: String) = db.from("community_tasks").select(Columns.raw(TASK)) {
        filter { eq("community_id", communityId) }; order("created_at", Order.ASCENDING)
    }.decodeList<CommunityTask>()

    @Serializable private data class Created(val id: String)

    suspend fun createTask(projectId: String, communityId: String, draft: TaskDraft, userId: String) {
        val task = db.from("community_tasks").insert(buildJsonObject {
            put("project_id", projectId); put("community_id", communityId); put("title", draft.title); put("description", draft.description)
            put("status", draft.status.raw); put("due_date", draft.due?.toString()); put("created_by", userId)
        }) { select(Columns.raw("id")) }.decodeSingle<Created>()
        setAssignees(task.id, emptyList(), draft.assignees, userId)
    }

    suspend fun updateTask(task: CommunityTask, draft: TaskDraft, userId: String, mayAssign: Boolean) {
        db.from("community_tasks").update(buildJsonObject {
            put("title", draft.title); put("description", draft.description); put("status", draft.status.raw); put("due_date", draft.due?.toString())
        }) { filter { eq("id", task.id) } }
        if (mayAssign) setAssignees(task.id, task.assignees.map { it.userId }, draft.assignees, userId)
    }

    suspend fun setStatus(taskId: String, status: TaskStatus) {
        db.from("community_tasks").update(buildJsonObject { put("status", status.raw) }) { filter { eq("id", taskId) } }
    }

    suspend fun deleteTask(id: String) { db.from("community_tasks").delete { filter { eq("id", id) } } }

    /** Selbst übernehmen. */
    suspend fun take(taskId: String, userId: String) = setAssignees(taskId, emptyList(), listOf(userId), userId)

    /** Selbst abgeben. */
    suspend fun release(taskId: String, userId: String) {
        db.from("community_task_assignees").delete { filter { eq("task_id", taskId); eq("user_id", userId) } }
    }

    private suspend fun setAssignees(taskId: String, old: List<String>, new: List<String>, userId: String) {
        val added = new.toSet() - old.toSet()
        val removed = old.toSet() - new.toSet()
        if (added.isNotEmpty()) db.from("community_task_assignees").insert(buildJsonArray {
            added.forEach { user -> add(buildJsonObject { put("task_id", taskId); put("user_id", user); put("assigned_by", userId) }) }
        })
        if (removed.isNotEmpty()) db.from("community_task_assignees").delete { filter { eq("task_id", taskId); isIn("user_id", removed.toList()) } }
    }

    // Kommentare (`task_comments`) — gleiche Form wie EventComment, `event_id` ist hier die Aufgabe.

    suspend fun comments(taskId: String) = db.from("task_comments").select(Columns.raw("id,event_id:task_id,user_id,body,created_at,profiles(user_id,display_name,avatar_url)")) {
        filter { eq("task_id", taskId) }; order("created_at", Order.ASCENDING)
    }.decodeList<EventComment>()

    suspend fun addComment(taskId: String, userId: String, body: String) {
        db.from("task_comments").insert(buildJsonObject { put("task_id", taskId); put("user_id", userId); put("body", body) })
    }

    suspend fun deleteComment(id: String) { db.from("task_comments").delete { filter { eq("id", id) } } }

    @Serializable private data class CommentRow(@SerialName("task_id") val taskId: String)

    /** Anzahl Kommentare je Aufgabe — für den Knopf unter der Karte. */
    suspend fun commentCounts(taskIds: List<String>): Map<String, Int> {
        if (taskIds.isEmpty()) return emptyMap()
        return db.from("task_comments").select(Columns.raw("task_id")) { filter { isIn("task_id", taskIds) } }
            .decodeList<CommentRow>().groupingBy { it.taskId }.eachCount()
    }
}
