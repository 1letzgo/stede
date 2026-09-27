package de.letzgo.stede.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*
import kotlinx.coroutines.launch
import java.time.LocalDate

/** Projekte und Aufgaben einer Gruppe; lädt beim ersten Öffnen des Reiters „Aufgaben“ — wie TasksModel in iOS. */
class TasksModel(private val communityId: String) {
    var projects by mutableStateOf<List<CommunityProject>?>(null); private set
    var tasks by mutableStateOf<List<CommunityTask>>(emptyList()); private set
    var commentCounts by mutableStateOf<Map<String, Int>>(emptyMap()); private set
    var lastError by mutableStateOf<String?>(null)

    suspend fun load() {
        runCatching { TaskApi.projects(communityId) to TaskApi.tasks(communityId) }
            .onSuccess { (list, all) ->
                tasks = all
                commentCounts = runCatching { TaskApi.commentCounts(all.map { it.id }) }.getOrDefault(commentCounts)
                projects = list; lastError = null
            }.onFailure {
                if (projects == null) projects = emptyList()
                lastError = it.message
            }
    }

    fun tasks(project: CommunityProject) = tasks.filter { it.projectId == project.id }

    /** Führt eine Änderung aus und lädt danach neu; Fehler landen in [lastError]. */
    suspend fun run(action: suspend () -> Unit): Boolean =
        runCatching { action() }.onFailure { lastError = it.message }.isSuccess.also { if (it) load() }
}

/** Wer was darf — spiegelt die RLS-Regeln, damit die Oberfläche nur Machbares anbietet. */
data class TaskPermissions(val userId: String?, val isAdmin: Boolean) {
    fun canEdit(task: CommunityTask) = isAdmin || (userId != null && task.createdBy.equals(userId, ignoreCase = true))
    fun canChangeStatus(task: CommunityTask) = canEdit(task) || task.isAssigned(userId)
}

object TaskFormat {
    fun due(day: LocalDate) = "bis ${day.format(Town.dayShort)}"

    @Composable fun color(status: TaskStatus) = when (status) {
        TaskStatus.Open -> C.amber
        TaskStatus.InProgress -> C.teal
        TaskStatus.Done -> C.green
    }

    fun icon(status: TaskStatus): ImageVector = when (status) {
        TaskStatus.Open -> Icons.Default.RadioButtonUnchecked
        TaskStatus.InProgress -> Icons.Default.Timelapse
        TaskStatus.Done -> Icons.Default.CheckCircle
    }
}

// Projektliste (Reiter)

/** Karte eines Projekts: Titel, Fortschritt, offene und eigene Aufgaben. */
@Composable
fun ProjectCard(project: CommunityProject, tasks: List<CommunityTask>, userId: String?, onClick: () -> Unit) {
    val done = tasks.count { it.status == TaskStatus.Done }
    val open = tasks.count { it.status == TaskStatus.Open }
    val working = tasks.count { it.status == TaskStatus.InProgress }
    val mine = tasks.count { it.status != TaskStatus.Done && it.isAssigned(userId) }
    val summary = if (tasks.isEmpty()) {
        if (project.isArchived) "Archiviert" else "Noch keine Aufgaben"
    } else buildList {
        add("$done von ${tasks.size} erledigt")
        if (working > 0) add("$working in Arbeit")
        if (open > 0) add("$open offen")
        if (project.isArchived) add("archiviert")
    }.joinToString(" · ")
    StedeCard(Modifier.alpha(if (project.isArchived) 0.7f else 1f), onClick = onClick) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                IconChip(Icons.Default.Checklist, C.amber)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(project.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                    Text(summary, fontSize = 12.sp, color = C.secondary)
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = C.tertiary)
            }
            if (project.description.isNotBlank()) Text(project.description, color = C.secondary, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (tasks.isNotEmpty()) {
                val share = done.toFloat() / tasks.size
                Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)).background(C.green.copy(alpha = 0.15f))) {
                    if (share > 0f) Box(Modifier.fillMaxWidth(share).fillMaxHeight().clip(RoundedCornerShape(50)).background(C.green))
                }
            }
            if (mine > 0) Pill(if (mine == 1) "1 Aufgabe für dich" else "$mine Aufgaben für dich", C.teal)
        }
    }
}

// Projekt

/** Aufgaben eines Projekts nach Status; jedes Mitglied legt Aufgaben an und übernimmt sie — wie ProjectDetailView in iOS. */
@Composable
fun ProjectScreen(projectId: String, model: TasksModel, members: List<Member>, permissions: TaskPermissions, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    val scope = rememberCoroutineScope()
    val project = model.projects?.firstOrNull { it.id == projectId }
    // Gelöscht (auch von anderen): zurück zur Liste.
    LaunchedEffect(project == null) { if (project == null) onBack() }
    if (project == null) return
    var onlyMine by remember { mutableStateOf(false) }
    var newTask by remember { mutableStateOf(false) }
    var editingTask by remember { mutableStateOf<CommunityTask?>(null) }
    var commentingTask by remember { mutableStateOf<CommunityTask?>(null) }
    var editingProject by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    val all = model.tasks(project)
    val tasks = if (onlyMine) all.filter { it.isAssigned(permissions.userId) } else all
    fun act(action: suspend () -> Unit) { scope.launch { model.run(action) } }

    Scaffold(topBar = {
        StedeTopBar(project.title, onBack, actions = {
            if (!project.isArchived) IconButton(onClick = { newTask = true }) { Icon(Icons.Default.Add, "Aufgabe anlegen") }
            if (permissions.isAdmin) Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Projekt verwalten") }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem({ Text("Projekt bearbeiten") }, { menu = false; editingProject = true }, leadingIcon = { Icon(Icons.Default.Edit, null) })
                    DropdownMenuItem({ Text(if (project.isArchived) "Wieder aktivieren" else "Archivieren") },
                        { menu = false; act { TaskApi.setProjectArchived(project.id, !project.isArchived) } },
                        leadingIcon = { Icon(if (project.isArchived) Icons.Default.Unarchive else Icons.Default.Archive, null) })
                    DropdownMenuItem({ Text("Projekt löschen", color = C.red) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Default.Delete, null, tint = C.red) })
                }
            }
        })
    }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (project.description.isNotBlank()) item {
                Text(project.description, color = C.secondary, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 4.dp))
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(false to "Alle", true to "Meine").forEach { (mine, label) ->
                        SelectionChip(label, onlyMine == mine, Modifier.weight(1f)) { onlyMine = mine }
                    }
                }
            }
            if (tasks.isEmpty()) item { InfoCard(if (onlyMine) "Dir ist hier keine Aufgabe zugewiesen." else "Noch keine Aufgaben. Leg die erste mit + an.") }
            TaskStatus.entries.forEach { status ->
                val group = tasks.filter { it.status == status }
                if (group.isNotEmpty()) {
                    item(key = "h${status.raw}") { SectionHeader("${status.title} ${group.size}", TaskFormat.icon(status)) }
                    items(group, key = { it.id }) { task ->
                        TaskCard(task, permissions, model.commentCounts[task.id] ?: 0,
                            onStatus = { s -> act { TaskApi.setStatus(task.id, s) } },
                            onTake = { permissions.userId?.let { me -> act { TaskApi.take(task.id, me) } } },
                            onRelease = { permissions.userId?.let { me -> act { TaskApi.release(task.id, me) } } },
                            onEdit = { editingTask = task },
                            onDelete = { act { TaskApi.deleteTask(task.id) } },
                            onComments = { commentingTask = task })
                    }
                }
            }
            model.lastError?.let { item { Text(it, color = C.red, fontSize = 13.sp) } }
        }
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text("Projekt löschen?") },
        text = { Text("Alle Aufgaben und Kommentare des Projekts werden entfernt.") },
        confirmButton = { TextButton({ confirmDelete = false; act { TaskApi.deleteProject(project.id) } }) { Text("Löschen", color = C.red) } },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Abbrechen") } })
    if (newTask) TaskEditorSheet(null, members, mayAssign = true, onDismiss = { newTask = false }) { draft ->
        val me = permissions.userId ?: return@TaskEditorSheet false
        model.run { TaskApi.createTask(project.id, project.communityId, draft, me) }
    }
    editingTask?.let { task ->
        val mayAssign = permissions.canEdit(task)
        TaskEditorSheet(task, members, mayAssign, onDismiss = { editingTask = null }) { draft ->
            val me = permissions.userId ?: return@TaskEditorSheet false
            model.run { TaskApi.updateTask(task, draft, me, mayAssign) }
        }
    }
    commentingTask?.let { task ->
        // Nach dem Schließen die Zähler unter den Karten auffrischen.
        CommentsSheet(task.title, CommentTarget.Task(task.id), canModerate = permissions.isAdmin) { commentingTask = null; scope.launch { model.load() } }
    }
    if (editingProject) ProjectEditorSheet(project, { editingProject = false }) { title, description ->
        model.run { TaskApi.updateProject(project.id, title, description) }
    }
}

/** Eine Aufgabe: Status, Titel, Fälligkeit, Zuständige; übernehmen, Status ändern, kommentieren — wie TaskCard in iOS. */
@Composable
fun TaskCard(
    task: CommunityTask, permissions: TaskPermissions, commentCount: Int, onStatus: (TaskStatus) -> Unit, onTake: () -> Unit,
    onRelease: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit, onComments: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val mine = task.isAssigned(permissions.userId)
    val done = task.status == TaskStatus.Done
    val mayStatus = permissions.canChangeStatus(task)
    StedeCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                // Kreis links: Tippen hakt ab (oder öffnet wieder) — nur für Zuständige, Ersteller und Admins.
                val tint = TaskFormat.color(task.status)
                if (mayStatus) IconButton(onClick = { onStatus(if (done) TaskStatus.Open else TaskStatus.Done) }, modifier = Modifier.size(32.dp)) {
                    Icon(TaskFormat.icon(task.status), if (done) "Wieder öffnen" else "Als erledigt markieren", tint = tint, modifier = Modifier.size(28.dp))
                } else Box(Modifier.size(32.dp), contentAlignment = Alignment.Center) { Icon(TaskFormat.icon(task.status), null, tint = tint, modifier = Modifier.size(28.dp)) }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(task.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = if (done) C.secondary else C.text,
                        textDecoration = if (done) TextDecoration.LineThrough else null)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Pill(task.status.title, tint)
                        task.due?.let { Pill(TaskFormat.due(it), if (task.isOverdue()) C.red else C.mudflat) }
                    }
                }
                if (mayStatus || mine) Box {
                    IconButton(onClick = { menu = true }, modifier = Modifier.size(32.dp)) { Icon(Icons.Default.MoreHoriz, "Aufgabe verwalten", tint = C.ink) }
                    DropdownMenu(menu, { menu = false }) {
                        if (mayStatus) TaskStatus.entries.filter { it != task.status }.forEach { s ->
                            DropdownMenuItem({ Text(s.title) }, { menu = false; onStatus(s) }, leadingIcon = { Icon(TaskFormat.icon(s), null) })
                        }
                        if (mine) DropdownMenuItem({ Text("Abgeben") }, { menu = false; onRelease() }, leadingIcon = { Icon(Icons.Default.DoNotTouch, null) })
                        if (permissions.canEdit(task)) {
                            DropdownMenuItem({ Text("Bearbeiten") }, { menu = false; onEdit() }, leadingIcon = { Icon(Icons.Default.Edit, null) })
                            DropdownMenuItem({ Text("Löschen", color = C.red) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Default.Delete, null, tint = C.red) })
                        }
                    }
                }
            }
            if (task.description.isNotBlank()) Text(task.description, color = C.secondary, fontSize = 15.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
            if (task.assignees.isEmpty()) SmallLabel(Icons.Default.PersonOutline, "Noch niemand zuständig", C.secondary)
            else Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(horizontalArrangement = Arrangement.spacedBy((-8).dp)) {
                    val border = C.surface
                    task.assignees.take(4).forEach { person ->
                        Box(Modifier.border(2.dp, border, CircleShape).padding(2.dp)) {
                            PersonAvatar(person.profile?.avatar, person.profile?.displayName ?: "?", size = 24.dp)
                        }
                    }
                }
                Text(task.assignees.mapNotNull { it.profile?.displayName }.sorted().joinToString(", "), fontSize = 12.sp, color = C.secondary,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!mine && !done && permissions.userId != null) ColorChip("Übernehmen", C.teal, icon = Icons.Default.PanTool, prominent = true, onClick = onTake)
                Spacer(Modifier.weight(1f))
                CommentsButton(commentCount, C.amber, onClick = onComments)
            }
        }
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text("Aufgabe löschen?") },
        confirmButton = { TextButton({ confirmDelete = false; onDelete() }) { Text("Löschen", color = C.red) } },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Abbrechen") } })
}

// Editoren

/** Neues oder geändertes Projekt: Titel und Beschreibung. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectEditorSheet(existing: CommunityProject?, onDismiss: () -> Unit, onSave: suspend (String, String) -> Boolean) {
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val canSave = title.isNotBlank() && !saving
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader(if (existing == null) "Neues Projekt" else "Projekt bearbeiten", leading = "Abbrechen" to onDismiss, trailing = (if (saving) "…" else "Sichern") to {
            if (canSave) {
                saving = true; error = null
                scope.launch {
                    if (onSave(title.trim(), description.trim())) onDismiss() else error = "Das Projekt konnte nicht gesichert werden."
                    saving = false
                }
            }
        })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            StedeCard {
                OutlinedTextField(title, { title = it.take(200) }, label = { Text("Titel, z. B. Sommerfest") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(description, { description = it }, label = { Text("Beschreibung (optional)") }, modifier = Modifier.fillMaxWidth(), minLines = 2, maxLines = 6)
            }
            error?.let { Text(it, color = C.red) }
        }
    }
}

/** Neue oder geänderte Aufgabe: Titel, Beschreibung, Status, Fälligkeit, Zuständige — wie TaskEditorView in iOS.
 *  Zuständige wählen dürfen Admins, Ersteller und wer eine neue Aufgabe anlegt ([mayAssign]). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskEditorSheet(existing: CommunityTask?, members: List<Member>, mayAssign: Boolean, onDismiss: () -> Unit, onSave: suspend (TaskDraft) -> Boolean) {
    val scope = rememberCoroutineScope()
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var status by remember { mutableStateOf(existing?.status ?: TaskStatus.Open) }
    var hasDue by remember { mutableStateOf(existing?.due != null) }
    var due by remember { mutableStateOf(existing?.due ?: Town.today().plusDays(7)) }
    val assignees = remember { mutableStateListOf<String>().apply { existing?.assignees?.forEach { add(it.userId) } } }
    var picking by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val canSave = title.isNotBlank() && !saving

    fun save() {
        saving = true; error = null
        val draft = TaskDraft(title.trim(), description.trim(), status, if (hasDue) due else null,
            if (mayAssign) assignees.toList() else existing?.assignees?.map { it.userId }.orEmpty())
        scope.launch {
            if (onSave(draft)) onDismiss() else error = "Die Aufgabe konnte nicht gesichert werden."
            saving = false
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader(if (existing == null) "Neue Aufgabe" else "Aufgabe bearbeiten", leading = "Abbrechen" to onDismiss,
            trailing = (if (saving) "…" else "Sichern") to { if (canSave) save() })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            StedeCard {
                OutlinedTextField(title, { title = it.take(300) }, label = { Text("Titel") }, modifier = Modifier.fillMaxWidth(), maxLines = 3)
                OutlinedTextField(description, { description = it }, label = { Text("Beschreibung (optional)") }, modifier = Modifier.fillMaxWidth(), minLines = 2, maxLines = 6)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TaskStatus.entries.forEach { s -> SelectionChip(s.title, status == s, Modifier.weight(1f), compact = true) { status = s } }
            }
            StedeCard {
                Row(verticalAlignment = Alignment.CenterVertically) { Text("Fällig bis", color = C.text, modifier = Modifier.weight(1f)); Switch(hasDue, { hasDue = it }) }
                if (hasDue) FormRow("Datum", due.format(Town.dayFull)) { picking = true }
            }
            if (mayAssign) {
                SectionHeader("Zuständig", Icons.Default.People)
                StedeCard(padding = 0.dp) {
                    val sorted = members.filter { it.isActive }.sortedBy { it.profile?.displayName ?: "" }
                    sorted.forEachIndexed { index, m ->
                        val name = m.profile?.displayName ?: "Mitglied"
                        val selected = m.userId in assignees
                        if (index > 0) Box(Modifier.fillMaxWidth().padding(start = 56.dp).height(1.dp).background(C.tertiary.copy(alpha = 0.2f)))
                        Row(Modifier.fillMaxWidth().clickable { if (selected) assignees.remove(m.userId) else assignees.add(m.userId) }
                            .padding(horizontal = CardPadding, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            PersonAvatar(m.profile?.avatar, name, size = 30.dp)
                            Text(name, color = C.text, modifier = Modifier.weight(1f))
                            if (selected) Icon(Icons.Default.Check, "Ausgewählt", tint = C.ink)
                        }
                    }
                }
                Text("Mitglieder können offene Aufgaben auch selbst übernehmen.", color = C.secondary, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
            }
            error?.let { Text(it, color = C.red) }
        }
    }
    if (picking) DatePickDialog(due, { picking = false }) { day -> due = day; picking = false }
}

/** Projekt-Reiter einer Gruppe: aktive Projekte, darunter das Archiv. */
@Composable
fun ProjectList(model: TasksModel, isAdmin: Boolean, userId: String?, onOpen: (CommunityProject) -> Unit) {
    // Wird als Inhalt eines LazyColumn-Items genutzt, daher eine schlichte Spalte.
    val projects = model.projects
    Column(verticalArrangement = Arrangement.spacedBy(Spacing)) {
        if (projects == null) { Loading(); return@Column }
        val active = projects.filter { !it.isArchived }
        val archived = projects.filter { it.isArchived }
        if (active.isEmpty()) InfoCard(if (isAdmin) "Noch kein Projekt. Leg eins mit + an – darin sammelt ihr die Aufgaben." else "Noch kein Projekt in dieser Gruppe.")
        active.forEach { p -> ProjectCard(p, model.tasks(p), userId) { onOpen(p) } }
        if (archived.isNotEmpty()) {
            SectionHeader("Archiv", Icons.Default.Archive)
            archived.forEach { p -> ProjectCard(p, model.tasks(p), userId) { onOpen(p) } }
        }
        model.lastError?.let { Text(it, color = C.red, fontSize = 13.sp) }
    }
}

