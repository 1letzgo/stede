@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package de.letzgo.stede.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stede.data.*
import de.letzgo.stede.Screen
import kotlinx.coroutines.launch

fun roleLabel(role: String) = when (role) { "owner" -> "Leitung"; "admin" -> "Admin"; else -> "Mitglied" }
fun statusLabel(status: String) = when (status) { "pending" -> "Wartet auf Freigabe"; "approved" -> "Freigegeben"; "rejected" -> "Abgelehnt"; "archived" -> "Archiviert"; else -> status }

/** Community-Tab wie CommunityListView: eigene zuerst, weitere, Mitmachen. Profil und Admin oben rechts als Sheet. */
@Composable
fun CommunityScreen(open: (Screen) -> Unit) {
    val scope = rememberCoroutineScope()
    // Zuerst der letzte Stand (CommunityCache), dann das Netz.
    var list by remember { mutableStateOf(CommunityCache.read<List<Community>>("communities", Session.userId)) }
    var error by remember { mutableStateOf<String?>(null) }
    var showAccount by remember { mutableStateOf(false) }
    var showAdmin by remember { mutableStateOf(false) }
    var showNew by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }
    var codeError by remember { mutableStateOf<String?>(null) }
    var showInvite by remember { mutableStateOf(false) }
    var myTasks by remember { mutableStateOf(CommunityCache.read<List<AssignedTask>>("my-tasks", Session.userId)) }
    suspend fun loadMyTasks() {
        val me = Session.userId ?: run { myTasks = null; return }
        runCatching { TaskApi.myTasks(me).filter { !it.projectArchived } }.onSuccess { myTasks = it; CommunityCache.write("my-tasks", me, it) }
    }
    LaunchedEffect(Session.userId, Session.memberships, Changes.version) { loadMyTasks() }
    LaunchedEffect(Session.userId, Session.memberships, Changes.version, showAdmin) {
        if (!showAdmin) Session.refreshAdminPending()
    }
    LaunchedEffect(Session.userId, Session.memberships, Changes.version) {
        runCatching { CommunityApi.communities(Tenants.current().id) }.onSuccess { list = it; error = null; CommunityCache.write("communities", Session.userId, it) }.onFailure { if (list == null) error = "Gruppen konnten nicht geladen werden." }
    }
    val town = Session.tenant?.municipality ?: Tenants.config.municipality
    Scaffold(topBar = {
        StedeTopBar("Gruppen", actions = {
            // Gefüllt, solange etwas zu tun ist (Anträge, Beitrittsanfragen); sonst nur Umriss.
            if (Session.showsAdmin) IconButton(onClick = { showAdmin = true }) {
                Icon(if (Session.adminPending > 0) Icons.Default.Verified else Icons.Outlined.Verified,
                    if (Session.adminPending > 0) "Admin, ${Session.adminPending} offen" else "Admin")
            }
        })
    }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (!Session.signedIn) item {
                StedeCard {
                    Text("Gruppen aus $town mit eigenem Kalender – Verein, Nachbarschaft, Chor.", color = C.secondary)
                    ColorChip("Anmelden", C.ink, Modifier.padding(top = 10.dp), icon = Icons.Default.AccountCircle, prominent = true) { showAccount = true }
                }
            }
            val all = list.orEmpty()
            val mineIds = Session.memberships.map { it.communityId }.toSet()
            val mine = all.filter { it.id in mineIds || it.createdBy == Session.userId }
            val others = all.filter { it !in mine && it.status == "approved" && it.visibility == "listed" }
            if (list == null && error == null) item { Loading() }
            // Ganz oben, eigene Kategorie „Meine Aufgaben“: eine Karte mit der Anzahl, öffnet die Übersicht nach Gruppen.
            val taskGroups = mine.filter { it.hasTasks && Session.membership(it.id)?.isActive == true }.map { it.id }.toSet()
            val assigned = myTasks?.filter { it.task.communityId in taskGroups }
            // Nur wenn dir etwas zugewiesen ist — sonst bleibt der Gruppen-Tab aufgeräumt.
            if (!assigned.isNullOrEmpty()) {
                item(key = "mytasksHeader") { SectionHeader("Meine Aufgaben", Icons.Default.Checklist) }
                item(key = "mytasks") {
                    val groups = assigned.map { it.task.communityId }.toSet().size
                    JoinRow(Icons.Default.Checklist, C.amber, "Aufgaben",
                        "${assigned.size} offen · ${if (groups == 1) "1 Gruppe" else "$groups Gruppen"}") { open(Screen.MyTasks) }
                }
            }
            if (mine.isNotEmpty()) {
                item { SectionHeader("Meine Gruppen", Icons.Default.Groups) }
                items(mine, key = { "m${it.id}" }) { c -> CommunityRow(c, Session.membership(c.id)) { open(Screen.CommunityDetail(c.id)) } }
            }
            if (others.isNotEmpty()) {
                item { SectionHeader(if (mine.isEmpty()) "Gruppen" else "Weitere Gruppen", Icons.Default.People) }
                items(others, key = { "o${it.id}" }) { c -> CommunityRow(c, null) { open(Screen.CommunityDetail(c.id)) } }
            } else if (mine.isEmpty() && list != null) {
                item { SectionHeader("Gruppen", Icons.Default.People) }
                item { InfoCard("Noch keine Gruppe in $town. Leg die erste an.") }
            }
            if (Session.signedIn) {
                item { SectionHeader("Mitmachen", Icons.Default.AddCircle) }
                item { JoinRow(Icons.Default.Key, C.teal, "Einladungscode eingeben", "Du hast einen Code für eine Gruppe bekommen.") { code = ""; codeError = null; showInvite = true } }
                item { JoinRow(Icons.Default.Add, C.green, "Gruppe gründen", "Für Verein, Nachbarschaft oder Chor – der Betreiber gibt sie frei.") { showNew = true } }
            }
            error?.let { item { Text(it, color = C.red, fontSize = 13.sp) } }
        }
    }
    if (showAccount) AccountSheet { showAccount = false }
    if (showAdmin) AdminSheet { showAdmin = false }
    if (showNew) CommunityEditorSheet(null) { showNew = false }
    if (showInvite) AlertDialog(onDismissRequest = { showInvite = false }, title = { Text("Einladungscode") },
        text = {
            Column {
                Text("Gib den Code ein, den du von der Gruppe bekommen hast.", color = C.secondary, fontSize = 14.sp)
                OutlinedTextField(code, { code = it.trim(); codeError = null }, Modifier.padding(top = 10.dp), placeholder = { Text("Code") }, singleLine = true, isError = codeError != null)
                codeError?.let { Text(it, color = C.red, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp)) }
            }
        },
        confirmButton = { TextButton(enabled = code.length >= 6, onClick = {
            scope.launch { runCatching { CommunityApi.byInvite(code) }.getOrNull()?.let { code = ""; showInvite = false; open(Screen.CommunityDetail(it.id)) } ?: run { codeError = "Zu diesem Code gibt es keine Gruppe." } }
        }) { Text("Öffnen") } },
        dismissButton = { TextButton({ showInvite = false }) { Text("Abbrechen") } })
}

/** Einzeilige Karte unter „Mitmachen“ wie `JoinRow` auf iOS: Symbol, Titel, Erklärung, Pfeil. */
@Composable
private fun JoinRow(icon: ImageVector, color: Color, title: String, detail: String, onClick: () -> Unit) {
    RowCard(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        IconChip(icon, color)
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
            Text(detail, color = C.secondary, fontSize = 14.sp)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = C.tertiary)
    }
}

@Composable
private fun CommunityRow(c: Community, m: Member?, onClick: () -> Unit) {
    StedeCard(onClick = onClick) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            CommunityAvatar(c.logoUrl, c.name)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(c.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (c.description.isNotBlank()) Text(c.description, color = C.secondary, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                CommunityPills(c, m, showsPolicy = m == null)
            }
        }
    }
}

@Composable
private fun CommunityPills(c: Community, m: Member?, showsPolicy: Boolean) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        c.memberCount?.let { Pill(if (it == 1) "1 Mitglied" else "$it Mitglieder", C.teal) }
        if (c.countywide) Pill("Kreisweit", C.heather)
        if (c.status == "pending") Pill("wartet auf Freigabe", C.amber)
        when {
            m?.status == "pending" -> Pill("Anfrage offen", C.amber)
            m?.isActive == true -> Pill(roleLabel(m.role), C.green)
        }
        if (showsPolicy) Pill(if (c.joinPolicy == "open") "offen" else "auf Anfrage", C.mudflat)
    }
}

enum class CommunityTab(val title: String) { Events("Termine"), Polls("Umfragen"), Tasks("Aufgaben"), Members("Mitglieder"), Settings("Einstellungen") }

/** Sichtbare Reiter: Umfragen und Aufgaben nur, wenn in den Einstellungen eingeschaltet. */
private fun visibleTabs(c: Community?) = CommunityTab.entries.filter {
    when (it) {
        CommunityTab.Polls -> c?.hasPolls ?: true
        CommunityTab.Tasks -> c?.hasTasks ?: false
        else -> true
    }
}

/** Reiter wie SectionSwitcher in iOS: nur Symbole, alle gleich breit; der Name bleibt als Beschreibung für Screenreader. */
@Composable
private fun CommunityTabs(tabs: List<CommunityTab>, selected: CommunityTab, onSelect: (CommunityTab) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        tabs.forEach { t ->
            val icon = when (t) {
                CommunityTab.Events -> Icons.Default.CalendarMonth
                CommunityTab.Polls -> Icons.Default.BarChart
                CommunityTab.Tasks -> Icons.Default.Checklist
                CommunityTab.Members -> Icons.Default.People
                CommunityTab.Settings -> Icons.Default.Settings
            }
            Box(Modifier.weight(1f).heightIn(min = ChipHeight).clip(RoundedCornerShape(50))
                .background(if (selected == t) C.deep else C.surface).clickable { onSelect(t) }, contentAlignment = Alignment.Center) {
                Icon(icon, t.title, tint = if (selected == t) Color.White else C.ink, modifier = Modifier.size(20.dp))
            }
        }
    }
}

/** Eine Community wie CommunityDetailView: Umschalter Termine · Umfragen · Aufgaben · Mitglieder · Einstellungen wie bei der Bahn
 *  (Umfragen und Aufgaben nur, wenn eingeschaltet); wer nicht Mitglied ist, sieht nur den Kopf mit Beitritt. */
@Composable
fun CommunityDetailScreen(id: String, onBack: () -> Unit, initialTab: CommunityTab = CommunityTab.Events) {
    val scope = rememberCoroutineScope()
    // Zuerst der letzte Stand der Gruppenseite (CommunityCache), dann das Netz.
    val cached = remember(id) { CommunityCache.read<GroupSnapshot>("group-${id.lowercase()}", Session.userId) }
    val today = remember { Town.today() }
    var c by remember { mutableStateOf(cached?.community) }
    var events by remember { mutableStateOf(cached?.events?.map { EventInfo.of(it, cached.community.name, cached.community.logoUrl) }
        ?.filter { !it.starts.withZoneSameInstant(Town.zone).toLocalDate().isBefore(today) && !it.isOver }) }
    var members by remember { mutableStateOf(cached?.members) }
    var helpers by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var past by remember { mutableStateOf<List<EventInfo>?>(null) }
    var hasMorePast by remember { mutableStateOf(true) }
    var loadingPast by remember { mutableStateOf(false) }
    var noMorePast by remember { mutableStateOf(false) }
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    // Nach „Frühere Termine“: Schlüssel des Termins, der vorher oben stand und nun unten am Rand stehen soll.
    var pastAnchor by remember { mutableStateOf<String?>(null) }
    val polls = remember(id) { PollsModel(id) }
    val tasks = remember(id) { TasksModel(id) }
    var newProject by remember { mutableStateOf(false) }
    // Geöffnetes Projekt: ersetzt die Gruppenseite wie ein Push; der Zustand hier bleibt erhalten.
    var openProject by remember { mutableStateOf<String?>(null) }
    var newPoll by remember { mutableStateOf(false) }
    var commentingPoll by remember { mutableStateOf<CommunityPoll?>(null) }
    var commentingEvent by remember { mutableStateOf<EventInfo?>(null) }
    var commentCounts by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var tab by remember { mutableStateOf(initialTab) }
    var openEvent by remember { mutableStateOf<EventInfo?>(null) }
    var newEvent by remember { mutableStateOf(false) }
    var editCommunity by remember { mutableStateOf(false) }
    var joinRequest by remember { mutableStateOf(false) }
    var confirmLeave by remember { mutableStateOf(false) }
    var showAccount by remember { mutableStateOf(false) }
    val membership = Session.membership(id)
    val isMember = membership?.isActive == true
    val isAdmin = membership?.isAdmin == true
    // Kommentarzahlen der geladenen Termine (kommende und frühere) mit eingeschalteten Kommentaren.
    suspend fun loadCommentCounts() {
        val ids = (events.orEmpty() + past.orEmpty()).filter { it.commentsEnabled }.map { it.id }
        commentCounts = runCatching { CommunityApi.commentCounts(ids) }.getOrDefault(commentCounts)
    }
    LaunchedEffect(id, Changes.version, Session.memberships) {
        runCatching { CommunityApi.community(id) }.onSuccess { c = it }
        if (isMember) {
            val from = Town.today().atStartOfDay(Town.zone).toOffsetDateTime().toString()
            val rawEvents = runCatching { CommunityApi.events(id, from) }.onSuccess { list -> events = list.map { EventInfo.of(it, c?.name ?: "", c?.logoUrl) }.filter { !it.isOver } }.getOrNull()
            val rawMembers = runCatching { CommunityApi.members(id) }.onSuccess { members = it }.getOrNull()
            val community = c
            if (rawEvents != null && rawMembers != null && community != null)
                CommunityCache.write("group-${id.lowercase()}", Session.userId, GroupSnapshot(community, rawMembers, rawEvents))
            helpers = runCatching { CommunityApi.helperCounts(events.orEmpty().filter { it.helpersNeeded > 0 }.map { it.id }) }.getOrDefault(emptyMap())
            loadCommentCounts()
            MyParticipation.load()
            if (polls.polls != null) polls.load()
            if (tasks.projects != null) tasks.load()
        }
    }
    // Frühere Termine: jeder Tipp auf den Chip holt die nächsten 20 (neueste zuerst geladen, oben chronologisch gezeigt).
    // Bisher abgerufene Zeilen — ohne die herausgefilterten, noch laufenden zählt der Versatz falsch.
    var pastFetched by remember { mutableLongStateOf(0L) }
    suspend fun loadPast(offset: Long) {
        if (loadingPast) return
        loadingPast = true
        noMorePast = false
        // Bis jetzt statt bis Mitternacht, damit heute Vorbeiges dabei ist; was noch läuft, steht oben.
        val before = Town.now().toOffsetDateTime().toString()
        val upcoming = events.orEmpty().map { it.id }.toSet()
        runCatching { CommunityApi.pastEvents(id, before, offset) }.onSuccess { page ->
            pastFetched = offset + page.size
            val infos = page.filter { it.id !in upcoming }.map { EventInfo.of(it, c?.name ?: "", c?.logoUrl) }
            past = if (offset == 0L) infos else past.orEmpty() + infos
            hasMorePast = page.size == 20
            noMorePast = page.isEmpty()
            val counts = runCatching { CommunityApi.helperCounts(page.filter { it.helpersNeeded > 0 }.map { it.id }) }.getOrDefault(emptyMap())
            helpers = helpers + counts
            loadCommentCounts()
        }.onFailure { if (past == null) past = emptyList() }
        loadingPast = false
    }
    // Grenze halten: der bisher älteste geladene (sonst der erste kommende) Termin rückt an den unteren Rand,
    // die neu geladenen früheren Termine stehen direkt darüber. Die Schlüssel folgen der Reihenfolge im Reiter Termine.
    LaunchedEffect(pastAnchor) {
        val key = pastAnchor ?: return@LaunchedEffect
        pastAnchor = null
        if (!isMember || tab != CommunityTab.Events) return@LaunchedEffect
        val keys = buildList {
            if (hasMorePast) add("earlier")
            if (noMorePast) add("noMorePast")
            past.orEmpty().asReversed().forEach { add("past${it.id}") }
            if (events == null || events!!.isEmpty()) add("placeholder")
            events.orEmpty().forEach { add(it.id) }
        }
        val index = keys.indexOf(key)
        if (index >= 0) listState.scrollItemToBottom(index)
    }
    // Umfragen und Aufgaben: erst beim ersten Öffnen des Reiters laden.
    LaunchedEffect(id, tab) {
        if (tab == CommunityTab.Polls && isMember && polls.polls == null) polls.load()
        if (tab == CommunityTab.Tasks && isMember && tasks.projects == null) tasks.load()
    }
    val community = c
    val tabs = visibleTabs(community)
    // Ausgeschaltete Funktion: zurück zu den Terminen.
    // Erst nach dem Laden der Gruppe, sonst fiele ein Start im Reiter „Aufgaben“ sofort zurück.
    LaunchedEffect(tabs) { if (community != null && tab !in tabs) tab = CommunityTab.Events }
    openProject?.let { projectId ->
        ProjectScreen(projectId, tasks, members.orEmpty().filter { it.isActive }, TaskPermissions(Session.userId, isAdmin)) { openProject = null }
        return
    }
    Scaffold(topBar = {
        StedeTopBar(community?.name ?: "Gruppe", onBack, actions = {
            if (isMember && tab == CommunityTab.Events) IconButton(onClick = { newEvent = true }) { Icon(Icons.Default.Add, "Termin anlegen") }
            if (isAdmin && tab == CommunityTab.Polls) IconButton(onClick = { newPoll = true }) { Icon(Icons.Default.Add, "Umfrage anlegen") }
            if (isAdmin && tab == CommunityTab.Tasks) IconButton(onClick = { newProject = true }) { Icon(Icons.Default.Add, "Projekt anlegen") }
        })
    }, containerColor = C.sand) { pad ->
        if (community == null) { Box(Modifier.padding(pad)) { Loading() }; return@Scaffold }
        Column(Modifier.padding(pad).fillMaxSize()) {
            if (isMember) Box(Modifier.padding(top = 16.dp, bottom = Spacing)) { CommunityTabs(tabs, tab) { tab = it } }
            LazyColumn(state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = if (isMember) 0.dp else 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                if (!isMember) {
                    item {
                        StedeCard {
                            CommunityHead(community, null)
                            Box(Modifier.padding(top = 10.dp)) {
                                when {
                                    !Session.signedIn -> ColorChip("Anmelden, um beizutreten", C.ink, icon = Icons.Default.AccountCircle, prominent = true) { showAccount = true }
                                    membership?.status == "pending" -> Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Icon(Icons.Default.HourglassTop, null, tint = C.secondary, modifier = Modifier.size(14.dp))
                                        Text("Anfrage gestellt – ein Admin bestätigt dich.", color = C.secondary, fontSize = 13.sp)
                                    }
                                    membership == null && community.status == "approved" -> ColorChip(if (community.joinPolicy == "open") "Beitreten" else "Beitritt anfragen", C.green, icon = Icons.Default.PersonAdd, prominent = true) {
                                        // Mit Freigabe: erst die optionale Kurzvorstellung, sonst sofort beitreten.
                                        if (community.joinPolicy == "open") scope.launch { runCatching { CommunityApi.join(id, Session.userId!!) }; Session.refresh(); Changes.bump() }
                                        else joinRequest = true
                                    }
                                }
                            }
                        }
                    }
                    return@LazyColumn
                }
                when (tab) {
                    CommunityTab.Events -> {
                        // Oben „Frühere Termine“ wie im Kalender; vergangene Termine chronologisch über den kommenden.
                        if (hasMorePast) item(key = "earlier") {
                            EarlierChip(loadingPast) {
                                val anchor = past?.lastOrNull()?.let { "past${it.id}" } ?: events?.firstOrNull()?.id
                                scope.launch {
                                    val before = past?.size ?: 0
                                    loadPast(pastFetched)
                                    if ((past?.size ?: 0) > before) pastAnchor = anchor
                                }
                            }
                        }
                        if (noMorePast) item(key = "noMorePast") {
                            Text("Keine früheren Termine.", color = C.secondary, fontSize = 13.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center, modifier = Modifier.fillMaxWidth())
                        }
                        items(past.orEmpty().asReversed(), key = { "past${it.id}" }) { e -> EventCard(e, helpers[e.id], onSignIn = { showAccount = true }, commentCount = commentCounts[e.id] ?: 0, onComments = { commentingEvent = e }, showsMenu = true) { openEvent = e } }
                        if (events == null) item { Loading() }
                        else if (events!!.isEmpty()) item { InfoCard("Noch keine anstehenden Termine.") }
                        items(events.orEmpty(), key = { it.id }) { e -> EventCard(e, helpers[e.id], onSignIn = { showAccount = true }, commentCount = commentCounts[e.id] ?: 0, onComments = { commentingEvent = e }, showsMenu = true) { openEvent = e } }
                    }
                    CommunityTab.Polls -> {
                        val list = polls.polls
                        if (list == null) item { Loading() }
                        else {
                            if (list.isEmpty()) item { InfoCard(if (isAdmin) "Noch keine Umfrage. Starte eine mit +." else "Noch keine Umfrage in dieser Gruppe.") }
                            items(list, key = { "poll${it.id}" }) { poll ->
                                PollCard(poll, polls.votes[poll.id].orEmpty(), Session.userId, isAdmin,
                                    onToggle = { option -> Session.userId?.let { user -> scope.launch { polls.toggle(option, poll, user) } } },
                                    onClose = { scope.launch { polls.close(poll) } },
                                    onDelete = { scope.launch { polls.delete(poll) } },
                                    commentCount = polls.commentCounts[poll.id] ?: 0,
                                    onComments = { commentingPoll = poll },
                                    onToggleComments = { scope.launch { polls.setComments(poll, !poll.commentsEnabled) } })
                            }
                            polls.lastError?.let { item { Text(it, color = C.red, fontSize = 13.sp) } }
                        }
                    }
                    CommunityTab.Tasks -> item { ProjectList(tasks, isAdmin, Session.userId) { openProject = it.id } }
                    CommunityTab.Members -> {
                        val all = members.orEmpty()
                        val pending = all.filter { it.status == "pending" }
                        if (isAdmin && pending.isNotEmpty()) {
                            item { SectionHeader("Anfragen", Icons.Default.PersonSearch) }
                            items(pending, key = { "p${it.id}" }) { m ->
                                RowCard {
                                    PersonAvatar(m.profile?.avatar, m.profile?.displayName ?: "Mitglied", C.amber)
                                    Column(Modifier.weight(1f)) {
                                        Text(m.profile?.displayName ?: "Mitglied", fontWeight = FontWeight.SemiBold, color = C.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                        JoinMessageText(m.joinMessage)
                                    }
                                    ColorChip(null, C.green, icon = Icons.Default.Check, prominent = true) { scope.launch { runCatching { CommunityApi.setMemberStatus(id, m.userId, "active") }; Changes.bump() } }
                                    ColorChip(null, C.red, icon = Icons.Default.Close) { scope.launch { runCatching { CommunityApi.removeMember(id, m.userId) }; Changes.bump() } }
                                }
                            }
                        }
                        item { SectionHeader("Mitglieder", Icons.Default.Groups) }
                        items(all.filter { it.isActive }.sortedWith(compareBy({ listOf("owner", "admin", "member").indexOf(it.role) }, { it.profile?.displayName })), key = { it.id }) { m ->
                            MemberRow(m, isAdmin && m.role != "owner" && m.userId != Session.userId, id)
                        }
                        if (isAdmin) community.inviteCode?.let { code -> item { InviteRow(community.name, code) } }
                    }
                    CommunityTab.Settings -> {
                        if (isAdmin) item { FeaturesCard(community) { polls, tasks -> c = community.copy(pollsEnabled = polls, tasksEnabled = tasks)
                            scope.launch {
                                runCatching { CommunityApi.setFeatures(id, polls, tasks) }
                                runCatching { CommunityApi.community(id) }.onSuccess { c = it }
                            }
                        } }
                        if (isAdmin) item { HeaderImagesManager(id) }
                        item {
                            StedeCard {
                                CommunityHead(community, null)
                                Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    SmallLabel(if (community.visibility == "listed") Icons.Default.Visibility else Icons.Default.VisibilityOff,
                                        if (community.visibility == "listed") "In der Gruppenliste sichtbar" else "Nur per Einladungscode", C.teal)
                                    SmallLabel(Icons.Default.PersonAdd, if (community.joinPolicy == "open") "Beitritt sofort" else "Admins bestätigen den Beitritt", C.teal)
                                    membership?.let { SmallLabel(Icons.Default.Badge, "Deine Rolle: ${roleLabel(it.role)}", C.teal) }
                                }
                                if (isAdmin) ColorChip("Bearbeiten", C.ink, Modifier.padding(top = 10.dp), icon = Icons.Default.Edit, prominent = true) { editCommunity = true }
                            }
                        }
                        item {
                            if (membership?.role != "owner") ColorChip("Gruppe verlassen", C.red, icon = Icons.AutoMirrored.Filled.Logout) { confirmLeave = true }
                            else Text("Als Leitung kannst du die Gruppe nicht verlassen – übergib die Rolle oder archiviere sie.", color = C.secondary, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
                        }
                    }
                }
            }
        }
    }
    openEvent?.let { e -> EventDetailSheet(e, helpers[e.id], onSignIn = { openEvent = null; showAccount = true }) { openEvent = null } }
    if (newEvent) EventEditorSheet(id, null) { newEvent = false }
    if (newProject) ProjectEditorSheet(null, { newProject = false }) { title, description ->
        val user = Session.userId ?: return@ProjectEditorSheet false
        tasks.run { TaskApi.createProject(id, title, description, user) }
    }
    if (newPoll) PollEditorSheet({ newPoll = false }) { draft ->
        val user = Session.userId ?: return@PollEditorSheet false
        polls.create(draft, user)
    }
    commentingPoll?.let { poll ->
        // Nach dem Schließen die Zähler unter den Karten auffrischen.
        CommentsSheet(poll.question, CommentTarget.Poll(poll.id), canModerate = isAdmin) { commentingPoll = null; scope.launch { polls.load() } }
    }
    commentingEvent?.let { e ->
        CommentsSheet(e.title, CommentTarget.Event(e.id), canModerate = canEdit(e)) { commentingEvent = null; scope.launch { loadCommentCounts() } }
    }
    if (editCommunity && community != null) CommunityEditorSheet(community) { editCommunity = false }
    if (joinRequest && community != null) JoinRequestDialog(community.name, { joinRequest = false }) { message ->
        val user = Session.userId ?: return@JoinRequestDialog false
        runCatching { CommunityApi.join(id, user, message) }.isSuccess.also { ok -> if (ok) { Session.refresh(); Changes.bump() } }
    }
    if (showAccount) AccountSheet { showAccount = false }
    if (confirmLeave) AlertDialog(onDismissRequest = { confirmLeave = false }, title = { Text("„${community?.name}“ verlassen?") },
        confirmButton = { TextButton({ confirmLeave = false; scope.launch { runCatching { CommunityApi.removeMember(id, Session.userId!!) }; Session.refresh(); tab = CommunityTab.Events; Changes.bump() } }) { Text("Verlassen", color = C.red) } },
        dismissButton = { TextButton({ confirmLeave = false }) { Text("Abbrechen") } })
}

/** Funktionen der Gruppe ein- und ausschalten (Admins/Leitung) — wie featuresCard in iOS. */
@Composable
private fun FeaturesCard(c: Community, onChange: (polls: Boolean, tasks: Boolean) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing)) {
        SectionHeader("Funktionen", Icons.Default.ToggleOn)
        StedeCard(padding = 0.dp) {
            Column(Modifier.padding(horizontal = CardPadding, vertical = 6.dp)) {
                FeatureRow(Icons.Default.BarChart, "Umfragen", c.hasPolls) { onChange(it, c.hasTasks) }
                Box(Modifier.fillMaxWidth().height(1.dp).background(C.tertiary.copy(alpha = 0.2f)))
                FeatureRow(Icons.Default.Checklist, "Aufgaben", c.hasTasks) { onChange(c.hasPolls, it) }
            }
        }
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, title: String, on: Boolean, onToggle: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, null, tint = C.ink, modifier = Modifier.size(20.dp))
        Text(title, color = C.text, modifier = Modifier.weight(1f))
        Switch(on, onToggle)
    }
}

/** „Frühere Termine“ wie im Kalender: volle Breite, Pfeil nach oben, beim Laden ein Spinner. */
@Composable
private fun EarlierChip(loading: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = ChipHeight).clip(RoundedCornerShape(50)).background(C.surface).clickable(enabled = !loading) { onClick() }.padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
        if (loading) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = C.ink)
        else Icon(Icons.Default.KeyboardArrowUp, null, tint = C.ink, modifier = Modifier.size(18.dp))
        Text("Frühere Termine", color = C.ink, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1)
    }
}

/** Kopf einer Community: Logo, Name, Pills, Beschreibung. */
@Composable
private fun CommunityHead(c: Community, m: Member?) {
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
        CommunityAvatar(c.logoUrl, c.name)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(c.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
            CommunityPills(c, m, showsPolicy = true)
        }
    }
    if (c.description.isNotBlank()) Text(c.description, color = C.secondary, fontSize = 15.sp, modifier = Modifier.padding(top = 10.dp))
}

@Composable
private fun InviteRow(name: String, code: String) {
    val context = LocalContext.current
    RowCard {
        Icon(Icons.Default.Key, null, tint = C.secondary, modifier = Modifier.size(14.dp))
        Text("Einladungscode $code", color = C.secondary, fontSize = 13.sp, modifier = Modifier.weight(1f))
        ActionChip("Einladen", Icons.Default.Share) {
            val send = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain")
                .putExtra(android.content.Intent.EXTRA_TEXT, "Tritt „$name“ in der stede-App bei – Einladungscode $code")
            context.startActivity(android.content.Intent.createChooser(send, "Einladen"))
        }
    }
}

@Composable
private fun MemberRow(m: Member, manageable: Boolean, communityId: String) {
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    RowCard {
        PersonAvatar(m.profile?.avatar, m.profile?.displayName ?: "Mitglied", if (m.role == "member") C.ink else C.heather)
        Text(m.profile?.displayName ?: "Mitglied", fontWeight = FontWeight.SemiBold, color = C.text, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (m.role != "member") Pill(roleLabel(m.role), C.heather)
        if (manageable) Box {
            IconButton(onClick = { menu = true }, modifier = Modifier.size(32.dp)) { Icon(Icons.Default.MoreHoriz, "Verwalten", tint = C.ink) }
            DropdownMenu(menu, { menu = false }) {
                if (m.role == "member") DropdownMenuItem({ Text("Zum Admin machen") }, { menu = false; scope.launch { runCatching { CommunityApi.setMemberRole(communityId, m.userId, "admin") }; Changes.bump() } })
                else DropdownMenuItem({ Text("Admin-Rolle entziehen") }, { menu = false; scope.launch { runCatching { CommunityApi.setMemberRole(communityId, m.userId, "member") }; Changes.bump() } })
                DropdownMenuItem({ Text("Entfernen", color = C.red) }, { menu = false; scope.launch { runCatching { CommunityApi.removeMember(communityId, m.userId) }; Changes.bump() } })
            }
        }
    }
}

/** Community anlegen (Vorschlag an den App-Admin) oder bearbeiten, mit Logo. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommunityEditorSheet(existing: Community?, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var listed by remember { mutableStateOf((existing?.visibility ?: "listed") == "listed") }
    var open by remember { mutableStateOf((existing?.joinPolicy ?: "approval") == "open") }
    var countywide by remember { mutableStateOf(existing?.countywide ?: false) }
    var logoPath by remember { mutableStateOf(existing?.logoPath) }
    var newLogo by remember { mutableStateOf<ByteArray?>(null) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { newLogo = jpeg(context, it, 600) } }
    fun save() = scope.launch {
        val user = Session.userId ?: return@launch
        saving = true; error = null
        runCatching {
            val tenant = Tenants.current()
            val visibility = if (listed) "listed" else "unlisted"; val policy = if (open) "open" else "approval"
            if (existing == null) {
                val created = CommunityApi.createCommunity(tenant.id, name.trim(), description.trim(), visibility, policy, countywide, user)
                newLogo?.let { CommunityApi.updateCommunity(created.id, created.name, created.description, visibility, policy, countywide, CommunityApi.uploadPhoto("community-logos", created.id, it)) }
            } else {
                val path = newLogo?.let { CommunityApi.uploadPhoto("community-logos", existing.id, it) } ?: logoPath
                CommunityApi.updateCommunity(existing.id, name.trim(), description.trim(), visibility, policy, countywide, path)
            }
            Session.refresh()
        }.onSuccess { Changes.bump(); onDismiss() }.onFailure { error = it.message }
        saving = false
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader(if (existing == null) "Neue Gruppe" else "Gruppe bearbeiten", leading = "Abbrechen" to onDismiss,
            trailing = (if (saving) "…" else "Sichern") to { if (name.isNotBlank() && !saving) save() })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            StedeCard {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (newLogo != null) AsyncImage(newLogo, null, Modifier.size(64.dp).clip(ChipShape), contentScale = ContentScale.Crop)
                    else CommunityAvatar(Backend.logoUrl(logoPath), name.ifBlank { "?" }, 64.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        ColorChip("Logo wählen", C.teal, icon = Icons.Default.Photo) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                        if (newLogo != null || logoPath != null) ColorChip("Entfernen", C.red, icon = Icons.Default.Delete) { newLogo = null; logoPath = null }
                    }
                }
            }
            StedeCard {
                OutlinedTextField(name, { name = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(description, { description = it }, label = { Text("Beschreibung") }, minLines = 3, modifier = Modifier.fillMaxWidth())
            }
            StedeCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text("In der Liste zeigen", color = C.text); Text("Sonst nur per Einladungscode auffindbar", color = C.secondary, fontSize = 13.sp) }
                    Switch(listed, { listed = it })
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text("Offen beitreten", color = C.text); Text("Sonst bestätigt ein Admin neue Mitglieder", color = C.secondary, fontSize = 13.sp) }
                    Switch(open, { open = it })
                }
            }
            StedeCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Kreisweit", color = C.text)
                        Text("Die Gruppe und ihre öffentlichen Termine erscheinen dann in allen ${Brand.current.regionName}-Gemeinden, nicht nur in ${Tenants.config.municipality}.", color = C.secondary, fontSize = 13.sp)
                    }
                    Switch(countywide, { countywide = it })
                }
            }
            if (existing == null) Text("Neue Gruppen gibt der App-Admin frei, bevor sie sichtbar werden.", color = C.secondary, fontSize = 13.sp)
            error?.let { Text(it, color = C.red) }
        }
    }
}

/** Admin: offene Communities (App-Admin) und offene Beitrittsanfragen (Community-Admins) — im Formstil des Profils. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdminSheet(onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf<List<Community>>(emptyList()) }
    var requests by remember { mutableStateOf<List<Pair<Community, Member>>>(emptyList()) }
    var version by remember { mutableIntStateOf(0) }
    LaunchedEffect(version) {
        val tenant = runCatching { Tenants.current() }.getOrNull() ?: return@LaunchedEffect
        if (Session.isTenantAdmin) pending = runCatching { CommunityApi.pending(tenant.id) }.getOrDefault(emptyList())
        val communities = runCatching { CommunityApi.communities(tenant.id) }.getOrDefault(emptyList()).associateBy { it.id }
        requests = Session.adminCommunityIds.flatMap { cid -> runCatching { CommunityApi.members(cid) }.getOrDefault(emptyList()).filter { it.status == "pending" }.mapNotNull { m -> communities[cid]?.let { it to m } } }
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader("Admin", trailing = "Fertig" to onDismiss)
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (Session.isTenantAdmin) {
                item { SectionHeader("Neue Gruppen", Icons.Default.VerifiedUser) }
                if (pending.isEmpty()) item { InfoCard("Keine offenen Vorschläge.") }
                items(pending, key = { it.id }) { c ->
                    StedeCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            CommunityAvatar(c.logoUrl, c.name); Text(c.name, fontWeight = FontWeight.SemiBold, color = C.text)
                        }
                        if (c.description.isNotBlank()) Text(c.description, color = C.secondary, fontSize = 14.sp, modifier = Modifier.padding(top = 6.dp))
                        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ColorChip("Freigeben", C.green, Modifier.weight(1f), icon = Icons.Default.Check) { scope.launch { runCatching { CommunityApi.setCommunityStatus(c.id, "approved") }; version++; Changes.bump() } }
                            ColorChip("Ablehnen", C.red, Modifier.weight(1f), icon = Icons.Default.Close) { scope.launch { runCatching { CommunityApi.setCommunityStatus(c.id, "rejected") }; version++; Changes.bump() } }
                        }
                    }
                }
            }
            if (Session.adminCommunityIds.isNotEmpty()) {
                item { SectionHeader("Beitrittsanfragen", Icons.Default.PersonAdd) }
                if (requests.isEmpty()) item { InfoCard("Keine offenen Anfragen.") }
                items(requests, key = { it.second.id }) { (c, m) ->
                    StedeCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            PersonAvatar(m.profile?.avatar, m.profile?.displayName ?: "Mitglied", C.amber)
                            Column {
                                Text(m.profile?.displayName ?: "Mitglied", fontWeight = FontWeight.SemiBold, color = C.text)
                                Pill(c.name, C.teal)
                                JoinMessageText(m.joinMessage)
                            }
                        }
                        Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            ColorChip("Annehmen", C.green, Modifier.weight(1f), icon = Icons.Default.Check) { scope.launch { runCatching { CommunityApi.setMemberStatus(c.id, m.userId, "active") }; version++; Changes.bump() } }
                            ColorChip("Ablehnen", C.red, Modifier.weight(1f), icon = Icons.Default.Close) { scope.launch { runCatching { CommunityApi.removeMember(c.id, m.userId) }; version++; Changes.bump() } }
                        }
                    }
                }
            }
        }
    }
}

/** Profil: Anmeldung per Magic Link, Name, Kalender-Abo, Abmelden, Konto löschen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountSheet(onDismiss: () -> Unit) {
    val scope = rememberCoroutineScope()
    val openIntent = rememberOpenIntent()
    val clipboard = LocalClipboardManager.current
    var email by remember { mutableStateOf("") }
    var sent by remember { mutableStateOf(false) }
    var usesPassword by remember { mutableStateOf(false) }
    var password by remember { mutableStateOf("") }
    var name by remember(Session.profile) { mutableStateOf(Session.profile?.displayName ?: "") }
    var token by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var uploading by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val pickAvatar = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let { u -> jpeg(context, u, 512)?.let { bytes -> scope.launch { uploading = true; Session.updateAvatar(bytes); uploading = false } } }
    }
    LaunchedEffect(Session.userId) { Session.userId?.let { id -> token = runCatching { CommunityApi.calendarToken(id) }.getOrNull() } }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader(if (Session.signedIn) "Konto" else "Anmelden", trailing = "Fertig" to onDismiss)
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (!Session.signedIn) {
                item {
                    StedeCard {
                        Text("Anmelden", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                        Text("Wir schicken dir einen Link per E-Mail. Öffne ihn auf diesem Gerät.", color = C.secondary, fontSize = 14.sp, modifier = Modifier.padding(vertical = 6.dp))
                        OutlinedTextField(email, { email = it.trim(); sent = false }, label = { Text("E-Mail") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        if (usesPassword) {
                            OutlinedTextField(password, { password = it }, label = { Text("Passwort") }, singleLine = true,
                                visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Password),
                                modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
                            ColorChip("Anmelden", C.teal, Modifier.fillMaxWidth().padding(top = 8.dp), icon = Icons.Default.Login, prominent = true, enabled = email.contains("@") && password.isNotEmpty()) {
                                scope.launch { Session.signIn(email, password) }
                            }
                        } else {
                            ColorChip(if (sent) "Link gesendet" else "Link senden", C.teal, Modifier.fillMaxWidth().padding(top = 8.dp), icon = Icons.Default.Email, prominent = true, enabled = email.contains("@") && !sent) {
                                scope.launch { sent = Session.sendMagicLink(email) }
                            }
                        }
                        // Für Konten mit Passwort (z. B. Prüfkonten von Apple und Google).
                        TextButton(onClick = { usesPassword = !usesPassword; password = "" }, modifier = Modifier.padding(top = 4.dp)) {
                            Text(if (usesPassword) "Stattdessen Anmeldelink schicken" else "Mit Passwort anmelden", color = C.ink, fontSize = 13.sp)
                        }
                        Session.error?.let { Text(it, color = C.red, fontSize = 13.sp) }
                    }
                }
                return@LazyColumn
            }
            item {
                StedeCard {
                    Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 12.dp)) {
                        Box(contentAlignment = Alignment.Center) {
                            PersonAvatar(Session.profile?.avatar, name.ifBlank { "?" }, size = 72.dp)
                            if (uploading) CircularProgressIndicator(Modifier.size(28.dp), color = C.teal)
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            ColorChip(if (Session.profile?.avatar == null) "Profilbild auswählen" else "Anderes Profilbild", C.teal, icon = Icons.Default.Photo, enabled = !uploading) {
                                pickAvatar.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                            }
                            if (Session.profile?.avatar != null) ColorChip("Entfernen", C.red, icon = Icons.Default.Delete, enabled = !uploading) {
                                scope.launch { uploading = true; Session.updateAvatar(null); uploading = false }
                            }
                        }
                    }
                    Text("Anzeigename", color = C.secondary, fontSize = 13.sp)
                    OutlinedTextField(name, { name = it }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    ColorChip("Sichern", C.teal, Modifier.fillMaxWidth().padding(top = 8.dp), enabled = name.isNotBlank() && name != Session.profile?.displayName) { scope.launch { Session.setName(name.trim()) } }
                }
            }
            item { SectionHeader("Kalender abonnieren", Icons.Default.CalendarMonth) }
            item {
                StedeCard {
                    Text("Deine Termine als Abo in der Kalender-App — aktualisiert sich selbst.", color = C.secondary, fontSize = 14.sp)
                    token?.let { t ->
                        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            ColorChip("Meine Zusagen", C.teal, Modifier.fillMaxWidth(), icon = Icons.Default.EventAvailable) { openIntent(Backend.webcalUrl(t, "mine")) }
                            ColorChip("Alle meine Gruppen", C.teal, Modifier.fillMaxWidth(), icon = Icons.Default.Groups) { openIntent(Backend.webcalUrl(t, "communities")) }
                            ColorChip("Link kopieren", C.mudflat, Modifier.fillMaxWidth(), icon = Icons.Default.ContentCopy) { clipboard.setText(AnnotatedString(Backend.feedUrl(t, "communities"))) }
                        }
                    } ?: Loading()
                }
            }
            item { SectionHeader("Konto", Icons.Default.Person) }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ColorChip("Abmelden", C.ink, Modifier.fillMaxWidth(), icon = Icons.Default.Logout) { scope.launch { Session.signOut() } }
                    ColorChip("Konto löschen", C.red, Modifier.fillMaxWidth(), icon = Icons.Default.DeleteForever) { confirmDelete = true }
                }
            }
        }
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text("Konto löschen?") },
        text = { Text("Dein Konto und deine Teilnahmen werden gelöscht. Gruppen, die nur du leitest, werden archiviert.") },
        confirmButton = { TextButton({ confirmDelete = false; scope.launch { if (Session.deleteAccount()) onDismiss() } }) { Text("Löschen", color = C.red) } },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Abbrechen") } })
}

/** Standardbilder verwalten (Leitung und Admins): Raster, hinzufügen mit Namen, löschen per langem Druck. */
@Composable
private fun HeaderImagesManager(communityId: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var images by remember { mutableStateOf<List<HeaderImage>>(emptyList()) }
    var pending by remember { mutableStateOf<ByteArray?>(null) }
    var label by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf<HeaderImage?>(null) }
    suspend fun load() { images = runCatching { CommunityApi.headerImages(communityId) }.getOrDefault(emptyList()) }
    LaunchedEffect(communityId) { load() }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let { pending = jpeg(context, it, 1600); label = "" }
    }
    StedeCard {
        SectionHeader("Standardbilder", Icons.Default.Collections)
        Text("Mitglieder können sie beim Anlegen eines Termins als Kopfbild wählen.", color = C.secondary, fontSize = 13.sp, modifier = Modifier.padding(vertical = 6.dp))
        val rows = (images.map { it as HeaderImage? } + listOf(null)).chunked(3)
        rows.forEach { row ->
            Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { img ->
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        if (img != null) {
                            AsyncImage(img.url, img.label, Modifier.fillMaxWidth().height(64.dp).clip(ChipShape)
                                .combinedClickable(onClick = {}, onLongClick = { confirmDelete = img }), contentScale = ContentScale.Crop)
                            Text(img.label, fontSize = 11.sp, color = C.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        } else {
                            Box(Modifier.fillMaxWidth().height(64.dp).clip(ChipShape).background(C.teal.copy(alpha = 0.12f))
                                .clickable(enabled = !busy) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                                contentAlignment = Alignment.Center) { Icon(if (busy) Icons.Default.HourglassTop else Icons.Default.Add, "Hinzufügen", tint = C.ink) }
                            Text("Hinzufügen", fontSize = 11.sp, color = C.secondary)
                        }
                    }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        if (images.isNotEmpty()) Text("Zum Löschen lange auf ein Bild drücken.", fontSize = 11.sp, color = C.tertiary)
        error?.let { Text(it, color = C.red, fontSize = 13.sp) }
    }
    pending?.let { data ->
        AlertDialog(onDismissRequest = { pending = null }, title = { Text("Name des Bildes") },
            text = { OutlinedTextField(label, { label = it }, placeholder = { Text("z. B. Rathaus") }, singleLine = true) },
            confirmButton = { TextButton({
                pending = null
                scope.launch {
                    busy = true
                    runCatching {
                        CommunityApi.addHeaderImage(data, label.trim().ifBlank { "Bild ${images.size + 1}" }, communityId, Session.userId!!, (images.maxOfOrNull { it.sortOrder } ?: 0) + 1)
                    }.onFailure { error = it.message }
                    load(); busy = false
                }
            }) { Text("Hinzufügen") } },
            dismissButton = { TextButton({ pending = null }) { Text("Abbrechen") } })
    }
    confirmDelete?.let { img ->
        AlertDialog(onDismissRequest = { confirmDelete = null }, title = { Text("„${img.label}“ löschen?") },
            text = { Text("Termine, die dieses Bild nutzen, verlieren ihr Kopfbild.") },
            confirmButton = { TextButton({ confirmDelete = null; scope.launch { runCatching { CommunityApi.deleteHeaderImage(img) }.onFailure { error = it.message }; load() } }) { Text("Löschen", color = C.red) } },
            dismissButton = { TextButton({ confirmDelete = null }) { Text("Abbrechen") } })
    }
}

/** Kurzvorstellung aus dem Beitrittsantrag, in Anführungszeichen unter dem Namen. */
@Composable
fun JoinMessageText(message: String?) {
    message?.takeIf { it.isNotBlank() }?.let {
        Text("„$it“", fontSize = 14.sp, color = C.secondary, fontStyle = androidx.compose.ui.text.font.FontStyle.Italic, modifier = Modifier.padding(top = 4.dp))
    }
}

/** Beitrittsantrag mit optionaler Kurzvorstellung — wie JoinRequestSheet auf iOS. */
@Composable
fun JoinRequestDialog(communityName: String, onDismiss: () -> Unit, onSend: suspend (String) -> Boolean) {
    val scope = rememberCoroutineScope()
    var message by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Beitritt anfragen") },
        text = {
            Column {
                Text("Die Admins von „$communityName“ bestätigen neue Mitglieder. Stell dich gern kurz vor – das ist freiwillig.", color = C.secondary, fontSize = 14.sp)
                OutlinedTextField(message, { message = it.take(500) }, Modifier.fillMaxWidth().padding(top = 10.dp), placeholder = { Text("Kurze Vorstellung (optional)") }, minLines = 3, maxLines = 8,
                    supportingText = { Text("${message.length}/500") })
                if (failed) Text("Die Anfrage konnte nicht gesendet werden.", color = C.red, fontSize = 13.sp)
            }
        },
        confirmButton = { TextButton(enabled = !sending, onClick = {
            sending = true; failed = false
            scope.launch { if (onSend(message)) onDismiss() else failed = true; sending = false }
        }) { Text(if (sending) "Wird gesendet …" else "Anfrage senden") } },
        dismissButton = { TextButton(onDismiss) { Text("Abbrechen") } })
}
