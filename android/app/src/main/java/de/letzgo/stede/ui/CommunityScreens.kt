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
import androidx.compose.material.icons.automirrored.filled.Logout
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
    val town = Session.tenant?.municipality ?: "Westerstede"
    Scaffold(topBar = {
        StedeTopBar("Community", actions = {
            if (Session.showsAdmin) IconButton(onClick = { showAdmin = true }) { Icon(Icons.Default.Verified, "Admin") }
            IconButton(onClick = { showAccount = true }) {
                val avatar = Session.profile?.avatar
                if (avatar != null) PersonAvatar(avatar, Session.profile?.displayName ?: "", size = 30.dp)
                else Icon(if (Session.signedIn) Icons.Default.AccountCircle else Icons.Outlined.AccountCircle, if (Session.signedIn) "Konto" else "Anmelden")
            }
        })
    }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (!Session.signedIn) item {
                StedeCard {
                    Text("Communities sind Gruppen aus $town mit eigenem Kalender – Verein, Nachbarschaft, Chor.", color = C.secondary)
                    ColorChip("Anmelden", C.ink, Modifier.padding(top = 10.dp), icon = Icons.Default.AccountCircle, prominent = true) { showAccount = true }
                }
            }
            val all = list.orEmpty()
            val mineIds = Session.memberships.map { it.communityId }.toSet()
            val mine = all.filter { it.id in mineIds || it.createdBy == Session.userId }
            val others = all.filter { it !in mine && it.status == "approved" && it.visibility == "listed" }
            if (list == null && error == null) item { Loading() }
            if (mine.isNotEmpty()) {
                item { SectionHeader("Meine Communities", Icons.Default.Groups) }
                items(mine, key = { "m${it.id}" }) { c -> CommunityRow(c, Session.membership(c.id)) { open(Screen.CommunityDetail(c.id)) } }
            }
            if (others.isNotEmpty()) {
                item { SectionHeader(if (mine.isEmpty()) "Communities" else "Weitere", Icons.Default.People) }
                items(others, key = { "o${it.id}" }) { c -> CommunityRow(c, null) { open(Screen.CommunityDetail(c.id)) } }
            } else if (mine.isEmpty() && list != null) {
                item { SectionHeader("Communities", Icons.Default.People) }
                item { InfoCard("Noch keine Community in $town. Leg die erste an.") }
            }
            if (Session.signedIn) {
                item { SectionHeader("Mitmachen", Icons.Default.AddCircle) }
                item {
                    StedeCard {
                        Text("Einladungscode erhalten?", fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = C.text)
                        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                            StedeTextField(code, { code = it.trim(); codeError = null }, "Code", Modifier.weight(1f))
                            ColorChip("Öffnen", C.teal, prominent = code.length >= 6, enabled = code.length >= 6) {
                                scope.launch { runCatching { CommunityApi.byInvite(code) }.getOrNull()?.let { code = ""; open(Screen.CommunityDetail(it.id)) } ?: run { codeError = "Kein Treffer für diesen Code." } }
                            }
                        }
                        codeError?.let { Text(it, color = C.red, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp)) }
                        HorizontalDivider(Modifier.padding(vertical = 10.dp), color = C.text.copy(alpha = 0.12f))
                        Text("Verein, Nachbarschaft oder Chor ohne eigene Community? Die Gemeinde gibt neue Communities frei.", color = C.secondary, fontSize = 15.sp)
                        ColorChip("Neue Community beantragen", C.ink, Modifier.padding(top = 10.dp), icon = Icons.Default.Add, prominent = true) { showNew = true }
                    }
                }
            }
            error?.let { item { Text(it, color = C.red, fontSize = 13.sp) } }
        }
    }
    if (showAccount) AccountSheet { showAccount = false }
    if (showAdmin) AdminSheet { showAdmin = false }
    if (showNew) CommunityEditorSheet(null) { showNew = false }
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
        if (c.status == "pending") Pill("wartet auf Freigabe", C.amber)
        when {
            m?.status == "pending" -> Pill("Anfrage offen", C.amber)
            m?.isActive == true -> Pill(roleLabel(m.role), C.green)
        }
        if (showsPolicy) Pill(if (c.joinPolicy == "open") "offen" else "auf Anfrage", C.mudflat)
    }
}

enum class CommunityTab(val title: String) { Events("Termine"), Archive("Archiv"), Members("Mitglieder"), Settings("Einstellungen") }

/** Reiter wie SectionSwitcher in iOS: drei gleich breite Chips, Einstellungen als schmales Zahnrad. */
@Composable
private fun CommunityTabs(selected: CommunityTab, onSelect: (CommunityTab) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        CommunityTab.entries.forEach { t ->
            if (t == CommunityTab.Settings) {
                Box(Modifier.heightIn(min = ChipHeight).width(56.dp).clip(RoundedCornerShape(50))
                    .background(if (selected == t) C.deep else C.surface).clickable { onSelect(t) }, contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.Settings, t.title, tint = if (selected == t) Color.White else C.ink, modifier = Modifier.size(20.dp))
                }
            } else SelectionChip(t.title, selected == t, Modifier.weight(1f), compact = true) { onSelect(t) }
        }
    }
}

/** Eine Community wie CommunityDetailView: Umschalter Termine · Mitglieder · Einstellungen wie bei der Bahn;
 *  wer nicht Mitglied ist, sieht nur den Kopf mit Beitritt. */
@Composable
fun CommunityDetailScreen(id: String, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var c by remember { mutableStateOf<Community?>(null) }
    var events by remember { mutableStateOf<List<EventInfo>?>(null) }
    var members by remember { mutableStateOf<List<Member>?>(null) }
    var helpers by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var past by remember { mutableStateOf<List<EventInfo>?>(null) }
    var hasMorePast by remember { mutableStateOf(true) }
    var loadingPast by remember { mutableStateOf(false) }
    var tab by remember { mutableStateOf(CommunityTab.Events) }
    var openEvent by remember { mutableStateOf<EventInfo?>(null) }
    var newEvent by remember { mutableStateOf(false) }
    var editCommunity by remember { mutableStateOf(false) }
    var confirmLeave by remember { mutableStateOf(false) }
    var showAccount by remember { mutableStateOf(false) }
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
    // Archiv: erst beim Öffnen des Reiters laden, seitenweise (20) beim Scrollen.
    suspend fun loadPast(offset: Long) {
        if (loadingPast) return
        loadingPast = true
        val before = Town.today().atStartOfDay(Town.zone).toOffsetDateTime().toString()
        runCatching { CommunityApi.pastEvents(id, before, offset) }.onSuccess { page ->
            val infos = page.map { EventInfo.of(it, c?.name ?: "", c?.logoUrl) }
            past = if (offset == 0L) infos else past.orEmpty() + infos
            hasMorePast = page.size == 20
            val counts = runCatching { CommunityApi.helperCounts(page.filter { it.helpersNeeded > 0 }.map { it.id }) }.getOrDefault(emptyMap())
            helpers = helpers + counts
        }.onFailure { if (past == null) past = emptyList() }
        loadingPast = false
    }
    LaunchedEffect(id, tab, Changes.version) {
        if (tab == CommunityTab.Archive && isMember) loadPast(0)
    }
    val community = c
    Scaffold(topBar = {
        StedeTopBar(community?.name ?: "Community", onBack, actions = {
            if (isMember && tab == CommunityTab.Events) IconButton(onClick = { newEvent = true }) { Icon(Icons.Default.Add, "Termin anlegen") }
        })
    }, containerColor = C.sand) { pad ->
        if (community == null) { Box(Modifier.padding(pad)) { Loading() }; return@Scaffold }
        Column(Modifier.padding(pad).fillMaxSize()) {
            if (isMember) Box(Modifier.padding(top = 16.dp, bottom = Spacing)) { CommunityTabs(tab) { tab = it } }
            LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = if (isMember) 0.dp else 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
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
                                        scope.launch { runCatching { CommunityApi.join(id, Session.userId!!) }; Session.refresh(); Changes.bump() }
                                    }
                                }
                            }
                        }
                    }
                    return@LazyColumn
                }
                when (tab) {
                    CommunityTab.Events -> {
                        if (events == null) item { Loading() }
                        else if (events!!.isEmpty()) item { InfoCard("Noch keine anstehenden Termine.") }
                        items(events.orEmpty(), key = { it.id }) { e -> EventCard(e, helpers[e.id], onSignIn = { showAccount = true }) { openEvent = e } }
                    }
                    CommunityTab.Archive -> {
                        val list = past
                        if (list == null) item { Loading() }
                        else if (list.isEmpty()) item { InfoCard("Keine vergangenen Termine.") }
                        else items(list, key = { "past${it.id}" }) { e ->
                            EventCard(e, helpers[e.id], onSignIn = { showAccount = true }) { openEvent = e }
                            // Letzte Karte sichtbar: nächste Seite nachladen.
                            if (e.id == list.last().id && hasMorePast) LaunchedEffect(list.size) { loadPast(list.size.toLong()) }
                        }
                        if (loadingPast && list != null) item { Loading() }
                    }
                    CommunityTab.Members -> {
                        val all = members.orEmpty()
                        val pending = all.filter { it.status == "pending" }
                        if (isAdmin && pending.isNotEmpty()) {
                            item { SectionHeader("Anfragen", Icons.Default.PersonSearch) }
                            items(pending, key = { "p${it.id}" }) { m ->
                                RowCard {
                                    PersonAvatar(m.profile?.avatar, m.profile?.displayName ?: "Mitglied", C.amber)
                                    Text(m.profile?.displayName ?: "Mitglied", fontWeight = FontWeight.SemiBold, color = C.text, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
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
                        if (isAdmin) item { HeaderImagesManager(id) }
                        item {
                            StedeCard {
                                CommunityHead(community, null)
                                Column(Modifier.padding(top = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    SmallLabel(if (community.visibility == "listed") Icons.Default.Visibility else Icons.Default.VisibilityOff,
                                        if (community.visibility == "listed") "In der Community-Liste sichtbar" else "Nur per Einladungscode", C.teal)
                                    SmallLabel(Icons.Default.PersonAdd, if (community.joinPolicy == "open") "Beitritt sofort" else "Admins bestätigen den Beitritt", C.teal)
                                    membership?.let { SmallLabel(Icons.Default.Badge, "Deine Rolle: ${roleLabel(it.role)}", C.teal) }
                                }
                                if (isAdmin) ColorChip("Bearbeiten", C.ink, Modifier.padding(top = 10.dp), icon = Icons.Default.Edit, prominent = true) { editCommunity = true }
                            }
                        }
                        item {
                            if (membership?.role != "owner") ColorChip("Community verlassen", C.red, icon = Icons.AutoMirrored.Filled.Logout) { confirmLeave = true }
                            else Text("Als Leitung kannst du die Community nicht verlassen – übergib die Rolle oder archiviere sie.", color = C.secondary, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
                        }
                    }
                }
            }
        }
    }
    openEvent?.let { e -> EventDetailSheet(e, helpers[e.id], onSignIn = { openEvent = null; showAccount = true }) { openEvent = null } }
    if (newEvent) EventEditorSheet(id, null) { newEvent = false }
    if (editCommunity && community != null) CommunityEditorSheet(community) { editCommunity = false }
    if (showAccount) AccountSheet { showAccount = false }
    if (confirmLeave) AlertDialog(onDismissRequest = { confirmLeave = false }, title = { Text("„${community?.name}“ verlassen?") },
        confirmButton = { TextButton({ confirmLeave = false; scope.launch { runCatching { CommunityApi.removeMember(id, Session.userId!!) }; Session.refresh(); tab = CommunityTab.Events; Changes.bump() } }) { Text("Verlassen", color = C.red) } },
        dismissButton = { TextButton({ confirmLeave = false }) { Text("Abbrechen") } })
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
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
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
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
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
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            PersonAvatar(m.profile?.avatar, m.profile?.displayName ?: "Mitglied", C.amber)
                            Column {
                                Text(m.profile?.displayName ?: "Mitglied", fontWeight = FontWeight.SemiBold, color = C.text)
                                Pill(c.name, C.teal)
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
