package de.letzgo.stede.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
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

/** Community-Tab wie CommunityListView: eigene, weitere, Einladungscode, Vorschlag. Profil und Admin oben rechts als Sheet. */
@Composable
fun CommunityScreen(open: (Screen) -> Unit) {
    val scope = rememberCoroutineScope()
    var list by remember { mutableStateOf<List<Community>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var showAccount by remember { mutableStateOf(false) }
    var showAdmin by remember { mutableStateOf(false) }
    var showNew by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }
    var codeError by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Session.userId, Session.memberships, Changes.version) {
        runCatching { CommunityApi.communities(Tenants.current().id) }.onSuccess { list = it; error = null }.onFailure { if (list == null) error = "Communities konnten nicht geladen werden." }
    }
    Scaffold(topBar = {
        StedeTopBar("Community", actions = {
            if (Session.showsAdmin) IconButton(onClick = { showAdmin = true }) { Icon(Icons.Default.VerifiedUser, "Admin") }
            IconButton(onClick = { showAccount = true }) { Icon(Icons.Default.AccountCircle, "Profil") }
        })
    }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (!Session.signedIn) item {
                StedeCard(highlighted = true) {
                    Text("Mach mit", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = C.text)
                    Text("Melde dich an, um Communities beizutreten, Termine zu sehen und zuzusagen.", color = C.secondary, modifier = Modifier.padding(vertical = 6.dp))
                    ColorChip("Anmelden", C.teal, Modifier.fillMaxWidth(), icon = Icons.Default.Login, prominent = true) { showAccount = true }
                }
            }
            val all = list.orEmpty()
            val mineIds = Session.memberships.map { it.communityId }.toSet()
            val mine = all.filter { it.id in mineIds || it.createdBy == Session.userId }
            val others = all.filter { it !in mine && it.status == "approved" && it.visibility == "listed" }
            if (list == null && error == null) item { Loading() }
            error?.let { item { InfoCard(it) } }
            if (mine.isNotEmpty()) {
                item { SectionHeader("Meine Communities", Icons.Default.Groups) }
                items(mine, key = { "m${it.id}" }) { c -> CommunityRow(c) { open(Screen.CommunityDetail(c.id)) } }
            }
            item { SectionHeader(if (mine.isEmpty()) "Communities in Westerstede" else "Weitere Communities", Icons.Default.Explore) }
            if (others.isEmpty() && list != null) item { InfoCard(if (all.isEmpty()) "Noch keine Community in Westerstede." else "Keine weiteren Communities.") }
            items(others, key = { "o${it.id}" }) { c -> CommunityRow(c) { open(Screen.CommunityDetail(c.id)) } }
            if (Session.signedIn) {
                item { SectionHeader("Einladung", Icons.Default.Key) }
                item {
                    StedeCard {
                        OutlinedTextField(code, { code = it.trim(); codeError = null }, label = { Text("Einladungscode") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        codeError?.let { Text(it, color = C.red, fontSize = 13.sp) }
                        ColorChip("Öffnen", C.teal, Modifier.fillMaxWidth().padding(top = 8.dp), enabled = code.isNotBlank()) {
                            scope.launch { runCatching { CommunityApi.byInvite(code) }.getOrNull()?.let { open(Screen.CommunityDetail(it.id)) } ?: run { codeError = "Kein Treffer für diesen Code." } }
                        }
                    }
                }
                item { ColorChip("Community vorschlagen", C.green, Modifier.fillMaxWidth(), icon = Icons.Default.AddCircle) { showNew = true } }
            }
        }
    }
    if (showAccount) AccountSheet { showAccount = false }
    if (showAdmin) AdminSheet { showAdmin = false }
    if (showNew) CommunityEditorSheet(null) { showNew = false }
}

@Composable
private fun CommunityRow(c: Community, onClick: () -> Unit) {
    val m = Session.membership(c.id)
    StedeCard(onClick = onClick) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            CommunityAvatar(c.logoUrl, c.name, 48.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(c.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (c.description.isNotBlank()) Text(c.description, color = C.secondary, fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    c.memberCount?.let { Pill(if (it == 1) "1 Mitglied" else "$it Mitglieder", C.teal) }
                    when {
                        c.status != "approved" -> Pill(statusLabel(c.status), C.amber)
                        m?.status == "pending" -> Pill("Anfrage offen", C.amber)
                        m?.isActive == true -> Pill(roleLabel(m.role), C.green)
                    }
                }
            }
        }
    }
}

enum class CommunityTab(val title: String) { Events("Termine"), Members("Mitglieder"), Settings("Einstellungen") }

/** Community-Detail: Kopf, Beitreten/Verlassen, Umschalter Termine/Mitglieder/Einstellungen, Plus oben rechts. */
@Composable
fun CommunityDetailScreen(id: String, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var c by remember { mutableStateOf<Community?>(null) }
    var events by remember { mutableStateOf<List<EventInfo>?>(null) }
    var members by remember { mutableStateOf<List<Member>?>(null) }
    var helpers by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var tab by remember { mutableStateOf(CommunityTab.Events) }
    var openEvent by remember { mutableStateOf<EventInfo?>(null) }
    var newEvent by remember { mutableStateOf(false) }
    var editCommunity by remember { mutableStateOf(false) }
    var confirmLeave by remember { mutableStateOf(false) }
    val membership = Session.membership(id)
    val isMember = membership?.isActive == true
    val isAdmin = membership?.isAdmin == true
    LaunchedEffect(id, Changes.version, Session.memberships) {
        runCatching { CommunityApi.community(id) }.onSuccess { c = it }
        if (isMember) {
            val from = Town.today().atStartOfDay(Town.zone).toOffsetDateTime().toString()
            runCatching { CommunityApi.events(id, from) }.onSuccess { list -> events = list.map { EventInfo.of(it, c?.name ?: "", c?.logoUrl) } }
            runCatching { CommunityApi.members(id) }.onSuccess { members = it }
            helpers = runCatching { CommunityApi.helperCounts(events.orEmpty().filter { it.helpersNeeded > 0 }.map { it.id }) }.getOrDefault(emptyMap())
            MyParticipation.load()
        }
    }
    val community = c
    Scaffold(topBar = {
        StedeTopBar(community?.name ?: "Community", onBack, actions = {
            if (isMember && community?.status == "approved") IconButton(onClick = { newEvent = true }) { Icon(Icons.Default.Add, "Termin anlegen") }
        })
    }, containerColor = C.sand) { pad ->
        if (community == null) { Box(Modifier.padding(pad)) { Loading() }; return@Scaffold }
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                Box(Modifier.padding(horizontal = 16.dp)) {
                    StedeCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            CommunityAvatar(community.logoUrl, community.name, 64.dp)
                            Column(Modifier.weight(1f)) {
                                Text(community.name, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.text)
                                Text(listOfNotNull(community.memberCount?.let { if (it == 1) "1 Mitglied" else "$it Mitglieder" }, if (community.joinPolicy == "open") "offen" else "mit Freigabe").joinToString(" · "), color = C.secondary, fontSize = 14.sp)
                            }
                        }
                        if (community.description.isNotBlank()) Text(community.description, color = C.text, modifier = Modifier.padding(top = 8.dp))
                        if (community.status != "approved") Box(Modifier.padding(top = 8.dp)) { Pill(statusLabel(community.status), C.amber) }
                        if (Session.signedIn && community.status == "approved") Box(Modifier.padding(top = 10.dp)) {
                            when {
                                membership == null -> ColorChip(if (community.joinPolicy == "open") "Beitreten" else "Beitritt anfragen", C.teal, Modifier.fillMaxWidth(), icon = Icons.Default.PersonAdd, prominent = true) {
                                    scope.launch { runCatching { CommunityApi.join(id, Session.userId!!) }; Session.refresh(); Changes.bump() }
                                }
                                membership.status == "pending" -> ColorChip("Anfrage zurückziehen", C.amber, Modifier.fillMaxWidth(), icon = Icons.Default.HourglassTop) {
                                    scope.launch { runCatching { CommunityApi.removeMember(id, Session.userId!!) }; Session.refresh() }
                                }
                                else -> {}
                            }
                        }
                    }
                }
            }
            if (!isMember) {
                item { Box(Modifier.padding(horizontal = 16.dp)) { InfoCard(if (Session.signedIn) "Termine und Mitglieder sehen nur Mitglieder." else "Melde dich an, um beizutreten.") } }
                return@LazyColumn
            }
            item { Switcher(if (isAdmin) CommunityTab.entries else listOf(CommunityTab.Events, CommunityTab.Members, CommunityTab.Settings), tab, { it.title }) { tab = it } }
            when (tab) {
                CommunityTab.Events -> {
                    if (events == null) item { Loading() }
                    else if (events!!.isEmpty()) item { Box(Modifier.padding(horizontal = 16.dp)) { InfoCard("Keine anstehenden Termine.") } }
                    items(events.orEmpty(), key = { it.id }) { e ->
                        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(e.starts.withZoneSameInstant(Town.zone).format(Town.dayLong), fontWeight = FontWeight.SemiBold, color = C.secondary, fontSize = 14.sp)
                            EventCard(e, helpers[e.id]) { openEvent = e }
                        }
                    }
                }
                CommunityTab.Members -> {
                    val all = members.orEmpty()
                    val pending = all.filter { it.status == "pending" }
                    if (isAdmin && pending.isNotEmpty()) {
                        item { Box(Modifier.padding(horizontal = 16.dp)) { SectionHeader("Anfragen (${pending.size})", Icons.Default.HourglassTop) } }
                        items(pending, key = { it.id }) { m ->
                            Box(Modifier.padding(horizontal = 16.dp)) {
                                StedeCard {
                                    Text(m.profile?.displayName ?: "Mitglied", fontWeight = FontWeight.SemiBold, color = C.text)
                                    Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        ColorChip("Annehmen", C.green, Modifier.weight(1f), icon = Icons.Default.Check) { scope.launch { runCatching { CommunityApi.setMemberStatus(id, m.userId, "active") }; Changes.bump() } }
                                        ColorChip("Ablehnen", C.red, Modifier.weight(1f), icon = Icons.Default.Close) { scope.launch { runCatching { CommunityApi.removeMember(id, m.userId) }; Changes.bump() } }
                                    }
                                }
                            }
                        }
                    }
                    item { Box(Modifier.padding(horizontal = 16.dp)) { SectionHeader("Mitglieder", Icons.Default.Groups) } }
                    items(all.filter { it.isActive }.sortedWith(compareBy({ listOf("owner", "admin", "member").indexOf(it.role) }, { it.profile?.displayName })), key = { it.id }) { m ->
                        Box(Modifier.padding(horizontal = 16.dp)) { MemberRow(m, isAdmin && m.role != "owner" && m.userId != Session.userId, id) }
                    }
                }
                CommunityTab.Settings -> {
                    item {
                        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                            if (isAdmin) {
                                community.inviteCode?.let { code -> InviteCard(code) }
                                ColorChip("Community bearbeiten", C.teal, Modifier.fillMaxWidth(), icon = Icons.Default.Edit) { editCommunity = true }
                            }
                            if (membership?.role != "owner") ColorChip("Community verlassen", C.red, Modifier.fillMaxWidth(), icon = Icons.Default.Logout) { confirmLeave = true }
                            else if (isAdmin) Text("Als Leitung kannst du die Community nicht verlassen.", color = C.secondary, fontSize = 13.sp)
                        }
                    }
                }
            }
        }
    }
    openEvent?.let { e -> EventDetailSheet(e, helpers[e.id]) { openEvent = null } }
    if (newEvent) EventEditorSheet(id, null) { newEvent = false }
    if (editCommunity && community != null) CommunityEditorSheet(community) { editCommunity = false }
    if (confirmLeave) AlertDialog(onDismissRequest = { confirmLeave = false }, title = { Text("Community verlassen?") },
        confirmButton = { TextButton({ confirmLeave = false; scope.launch { runCatching { CommunityApi.removeMember(id, Session.userId!!) }; Session.refresh(); onBack() } }) { Text("Verlassen", color = C.red) } },
        dismissButton = { TextButton({ confirmLeave = false }) { Text("Abbrechen") } })
}

@Composable
private fun InviteCard(code: String) {
    val clipboard = LocalClipboardManager.current
    StedeCard {
        Text("Einladungscode", color = C.secondary, fontSize = 13.sp)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(code, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.text, modifier = Modifier.weight(1f))
            IconButton(onClick = { clipboard.setText(AnnotatedString(code)) }) { Icon(Icons.Default.ContentCopy, "Kopieren", tint = C.ink) }
        }
    }
}

@Composable
private fun MemberRow(m: Member, manageable: Boolean, communityId: String) {
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    StedeCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val name = m.profile?.displayName ?: "Mitglied"
            CommunityAvatar(null, name, 36.dp)
            Text(name, color = C.text, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Pill(roleLabel(m.role), if (m.role == "member") C.teal else C.green)
            if (manageable) Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Verwalten", tint = C.secondary) }
                DropdownMenu(menu, { menu = false }) {
                    if (m.role == "member") DropdownMenuItem({ Text("Zum Admin machen") }, { menu = false; scope.launch { runCatching { CommunityApi.setMemberRole(communityId, m.userId, "admin") }; Changes.bump() } })
                    else DropdownMenuItem({ Text("Admin-Rechte entziehen") }, { menu = false; scope.launch { runCatching { CommunityApi.setMemberRole(communityId, m.userId, "member") }; Changes.bump() } })
                    DropdownMenuItem({ Text("Entfernen", color = C.red) }, { menu = false; scope.launch { runCatching { CommunityApi.removeMember(communityId, m.userId) }; Changes.bump() } })
                }
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
                val created = CommunityApi.createCommunity(tenant.id, name.trim(), description.trim(), visibility, policy, user)
                newLogo?.let { CommunityApi.updateCommunity(created.id, created.name, created.description, visibility, policy, CommunityApi.uploadPhoto("community-logos", created.id, it)) }
            } else {
                val path = newLogo?.let { CommunityApi.uploadPhoto("community-logos", existing.id, it) } ?: logoPath
                CommunityApi.updateCommunity(existing.id, name.trim(), description.trim(), visibility, policy, path)
            }
            Session.refresh()
        }.onSuccess { Changes.bump(); onDismiss() }.onFailure { error = it.message }
        saving = false
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand) {
        SheetHeader(if (existing == null) "Neue Community" else "Community bearbeiten", leading = "Abbrechen" to onDismiss,
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
            if (existing == null) Text("Neue Communities gibt der App-Admin frei, bevor sie sichtbar werden.", color = C.secondary, fontSize = 13.sp)
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
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand) {
        SheetHeader("Admin", trailing = "Fertig" to onDismiss)
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (Session.isTenantAdmin) {
                item { SectionHeader("Neue Communities", Icons.Default.VerifiedUser) }
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
                        Text(m.profile?.displayName ?: "Mitglied", fontWeight = FontWeight.SemiBold, color = C.text)
                        Text(c.name, color = C.secondary, fontSize = 14.sp)
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
    var name by remember(Session.profile) { mutableStateOf(Session.profile?.displayName ?: "") }
    var token by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    LaunchedEffect(Session.userId) { Session.userId?.let { id -> token = runCatching { CommunityApi.calendarToken(id) }.getOrNull() } }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand) {
        SheetHeader("Profil", trailing = "Fertig" to onDismiss)
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (!Session.signedIn) {
                item {
                    StedeCard {
                        Text("Anmelden", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                        Text("Wir schicken dir einen Link per E-Mail. Öffne ihn auf diesem Gerät.", color = C.secondary, fontSize = 14.sp, modifier = Modifier.padding(vertical = 6.dp))
                        OutlinedTextField(email, { email = it.trim(); sent = false }, label = { Text("E-Mail") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                        ColorChip(if (sent) "Link gesendet" else "Link senden", C.teal, Modifier.fillMaxWidth().padding(top = 8.dp), icon = Icons.Default.Email, prominent = true, enabled = email.contains("@") && !sent) {
                            scope.launch { sent = Session.sendMagicLink(email) }
                        }
                        Session.error?.let { Text(it, color = C.red, fontSize = 13.sp) }
                    }
                }
                return@LazyColumn
            }
            item {
                StedeCard {
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
                            ColorChip("Alle meine Communities", C.teal, Modifier.fillMaxWidth(), icon = Icons.Default.Groups) { openIntent(Backend.webcalUrl(t, "communities")) }
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                ColorChip("Link kopieren", C.mudflat, Modifier.weight(1f), icon = Icons.Default.ContentCopy) { clipboard.setText(AnnotatedString(Backend.feedUrl(t, "communities"))) }
                                ColorChip("Neuer Link", C.amber, Modifier.weight(1f), icon = Icons.Default.Refresh) { scope.launch { Session.userId?.let { token = runCatching { CommunityApi.rotateCalendarToken(it) }.getOrNull() } } }
                            }
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
        text = { Text("Dein Konto und deine Teilnahmen werden gelöscht. Communities, die nur du leitest, werden archiviert.") },
        confirmButton = { TextButton({ confirmDelete = false; scope.launch { if (Session.deleteAccount()) onDismiss() } }) { Text("Löschen", color = C.red) } },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Abbrechen") } })
}
