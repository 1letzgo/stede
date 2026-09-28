package de.letzgo.stede.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.Screen
import de.letzgo.stede.data.*
import kotlinx.coroutines.launch

/** „Meine Aufgaben“ wie MyTasksView in iOS: alle eigenen offenen Aufgaben, nach Gruppen sortiert —
 *  je Gruppe ein Kopf (öffnet deren Aufgaben), darunter die Aufgaben. */
@Composable
fun MyTasksScreen(open: (Screen) -> Unit, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val scope = rememberCoroutineScope()
    // Zuerst der letzte Stand (CommunityCache), dann das Netz.
    var communities by remember { mutableStateOf(CommunityCache.read<List<Community>>("communities", Session.userId)) }
    var tasks by remember { mutableStateOf(CommunityCache.read<List<AssignedTask>>("my-tasks", Session.userId)) }
    var counts by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var error by remember { mutableStateOf<String?>(null) }
    var commentingTask by remember { mutableStateOf<CommunityTask?>(null) }

    suspend fun load() {
        val me = Session.userId ?: run { tasks = null; return }
        runCatching { CommunityApi.communities(Tenants.current().id) }.onSuccess { communities = it; CommunityCache.write("communities", me, it) }
        runCatching { TaskApi.myTasks(me).filter { !it.projectArchived } }
            .onSuccess { list -> tasks = list; error = null; CommunityCache.write("my-tasks", me, list); runCatching { TaskApi.commentCounts(list.map { it.task.id }) }.onSuccess { counts = it } }
            .onFailure { error = "Aufgaben konnten nicht geladen werden." }
    }
    // Changes.bump lädt auch die Karte in der Gruppenliste (Anzahl) neu.
    fun act(action: suspend () -> Unit) { scope.launch { runCatching { action() }.onFailure { error = it.message }; Changes.bump() } }
    LaunchedEffect(Session.userId, Changes.version) { load() }

    // Eigene Gruppen mit eingeschalteten Aufgaben; Aufgaben ohne sichtbare Gruppe (andere Gemeinde) fallen weg.
    val groups = communities.orEmpty()
        .filter { it.hasTasks && Session.membership(it.id)?.isActive == true }
        .mapNotNull { c -> tasks.orEmpty().filter { it.task.communityId == c.id }.takeIf { it.isNotEmpty() }?.let { c to it } }

    Scaffold(topBar = { StedeTopBar("Meine Aufgaben", onBack) }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (tasks == null && error == null) item { Loading() }
            if (tasks != null && groups.isEmpty()) item { InfoCard("Gerade ist dir keine offene Aufgabe zugewiesen.") }
            groups.forEach { (g, own) ->
                item(key = "g${g.id}") {
                    RowCard(Modifier.fillMaxWidth().clickable { open(Screen.CommunityDetail(g.id, tasks = true)) }) {
                        CommunityAvatar(g.logoUrl, g.name, size = 28.dp)
                        Text(g.name, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = C.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(if (own.size == 1) "1 Aufgabe" else "${own.size} Aufgaben", fontSize = 12.sp, color = C.secondary)
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = C.tertiary)
                    }
                }
                items(own, key = { "t${it.task.id}" }) { item ->
                    val t = item.task
                    val m = Session.membership(g.id)
                    TaskCard(t, TaskPermissions(Session.userId, m?.isAdmin == true), counts[t.id] ?: 0,
                        onStatus = { s -> act { TaskApi.setStatus(t.id, s) } },
                        onTake = {},
                        onRelease = { Session.userId?.let { me -> act { TaskApi.release(t.id, me) } } },
                        onEdit = null,
                        onDelete = { act { TaskApi.deleteTask(t.id) } },
                        onComments = { commentingTask = t },
                        context = item.projectTitle)
                }
            }
            error?.let { item { Text(it, color = C.red, fontSize = 13.sp) } }
        }
    }
    commentingTask?.let { t ->
        CommentsSheet(t.title, CommentTarget.Task(t.id), canModerate = Session.membership(t.communityId)?.isAdmin == true) {
            commentingTask = null; scope.launch { load() }
        }
    }
}
