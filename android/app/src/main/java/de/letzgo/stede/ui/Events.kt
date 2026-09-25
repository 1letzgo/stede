@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)

package de.letzgo.stede.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import de.letzgo.stede.data.*
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime

/** Zähler, den Editoren nach dem Speichern erhöhen — Kalender und Community laden dann neu. */
object Changes { var version by mutableIntStateOf(0); fun bump() { version++ } }

/** Eigene Teilnahmen, für alle Karten geteilt. */
object MyParticipation {
    var byEvent by mutableStateOf<Map<String, Participation>>(emptyMap()); private set
    suspend fun load() { val id = Session.userId ?: run { byEvent = emptyMap(); return }; runCatching { byEvent = CommunityApi.myParticipations(id).associateBy { it.eventId } } }
    suspend fun set(eventId: String, status: String?, helping: Boolean) {
        val id = Session.userId ?: return
        CommunityApi.setParticipation(eventId, id, status, helping)
        byEvent = if (status == null) byEvent - eventId else byEvent + (eventId to Participation(eventId, id, status, helping && status != "declined"))
    }
}

fun timeLabel(e: EventInfo): String {
    val start = e.starts.withZoneSameInstant(Town.zone)
    val end = e.ends?.withZoneSameInstant(Town.zone)
    return when {
        end == null -> start.format(Town.hm)
        end.toLocalDate() == start.toLocalDate() -> "${start.format(Town.hm)}–${end.format(Town.hm)}"
        else -> "${start.format(Town.hm)} – ${end.format(Town.dayShort)} ${end.format(Town.hm)}"
    }
}
fun longTimeLabel(e: EventInfo): String {
    val start = e.starts.withZoneSameInstant(Town.zone)
    val end = e.ends?.withZoneSameInstant(Town.zone)
    return start.format(Town.fmt("EEEE, d. MMMM yyyy, HH:mm")) + (end?.let { " bis ${it.format(Town.hm)} Uhr" } ?: " Uhr")
}
fun canEdit(e: EventInfo) = Session.userId != null && (e.createdBy == Session.userId || (e.communityId != null && e.communityId in Session.adminCommunityIds))

/** Die eine Terminkarte für Community-Termine — in Community und Kalender identisch (CommunityEventCard). */
@Composable
fun EventCard(e: EventInfo, helpers: Int?, onSignIn: () -> Unit = {}, onOpen: () -> Unit) {
    val going = MyParticipation.byEvent[e.id]?.status == "going"
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    // Tippen öffnet die Details, langes Drücken teilt (wie das Kontextmenü in iOS).
    Column(Modifier.cardSurface().goingOutline(going)
        .combinedClickable(onClick = onOpen, onLongClick = { scope.launch { EventShare.share(context, e) } })) {
        e.imageUrl?.let { EventPhoto(it, 170.dp) }
        EventBody(e, helpers, compact = true, onSignIn = onSignIn)
    }
}

/** Inhalt unter dem Foto — in Karte (gekürzt) und Detail (voll) gleich aufgebaut. */
@Composable
private fun EventBody(e: EventInfo, helpers: Int?, compact: Boolean, onSignIn: () -> Unit) {
    val tint = if (e.isCancelled) C.red else C.teal
    val count = helpers ?: 0
    // Vorbei, sobald Ende (oder Beginn ohne Ende) verstrichen ist — dann keine Zusagen mehr.
    val isPast = (e.ends ?: e.starts).isBefore(Town.now())
    Column(Modifier.padding(CardPadding), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            CommunityAvatar(e.logoUrl, e.community)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(e.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text,
                    textDecoration = if (e.isCancelled) androidx.compose.ui.text.style.TextDecoration.LineThrough else null)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Pill(timeLabel(e), tint)
                    if (e.isCancelled) Pill("abgesagt", C.red) else if (isPast) Pill("vorbei", C.mudflat)
                    if (e.helpersNeeded > 0) Pill(if (count >= e.helpersNeeded) "Helfer komplett" else "Helfer $count/${e.helpersNeeded}", if (count >= e.helpersNeeded) C.green else C.heather)
                }
            }
            if (!e.isPublic) Icon(Icons.Default.Lock, "Nur für Mitglieder", tint = C.secondary, modifier = Modifier.size(14.dp))
        }
        // Karte: Ort linksbündig direkt unter der Kopfzeile, grau, einzeilig — wie bei den Stadt-Terminen.
        if (compact) e.location?.takeIf { it.isNotBlank() }?.let { LocationLine(it) }
        if (e.description.isNotBlank()) Text(e.description, color = C.secondary, fontSize = 15.sp, maxLines = if (compact) 4 else Int.MAX_VALUE, overflow = TextOverflow.Ellipsis)
        if (!compact) {
            SmallLabel(Icons.Default.Schedule, longTimeLabel(e), tint)
            SmallLabel(Icons.Default.Groups, e.community, tint)
        }
        if (!compact) e.location?.takeIf { it.isNotBlank() }?.let { SmallLabel(Icons.Default.Place, it, tint) }
        if (!e.isCancelled && !isPast) {
            if (Session.signedIn) ParticipationRow(e, helpers)
            else ColorChip("Anmelden, um zuzusagen", C.ink, icon = Icons.Default.AccountCircle) { onSignIn() }
        }
    }
}

@Composable
fun SmallLabel(icon: ImageVector, text: String, tint: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(14.dp))
        Text(text, fontSize = 13.sp, color = C.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

/** Ich komme / Vielleicht / Absage als Symbole; Helfer darüber in eigenem, erklärtem Kasten. */
@Composable
fun ParticipationRow(e: EventInfo, helpers: Int?, onChange: () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    val mine = MyParticipation.byEvent[e.id]
    val status = mine?.status
    val helping = mine?.helping == true
    val showHelp = e.helpersNeeded > 0 && (helping || (helpers ?: 0) < e.helpersNeeded)
    fun set(s: String?, help: Boolean) = scope.launch { runCatching { MyParticipation.set(e.id, s, help) }; Changes.bump(); onChange() }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (showHelp) {
            val open = (e.helpersNeeded - (helpers ?: 0)).coerceAtLeast(0)
            Row(Modifier.fillMaxWidth().background(C.heather.copy(alpha = 0.1f), RoundedCornerShape(14.dp)).padding(10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Default.VolunteerActivism, null, tint = C.heather, modifier = Modifier.size(20.dp))
                Column(Modifier.weight(1f)) {
                    Text(if (helping) "Du hilfst mit" else "Hier werden Helfer gesucht", fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = C.text)
                    Text(if (helping) "Danke! Tippe erneut, um dich auszutragen." else "Noch $open von ${e.helpersNeeded} Plätzen frei", fontSize = 12.sp, color = C.secondary)
                }
                ColorChip(if (helping) "Eingetragen" else "Mithelfen", C.heather, icon = if (helping) Icons.Default.Check else Icons.Default.PanTool, prominent = helping) {
                    if (helping) set(status ?: "going", false) else set(if (status == null || status == "declined") "going" else status, true)
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            ColorChip(null, C.green, Modifier.weight(1f), icon = Icons.Default.Check, selected = status == "going") { set(if (status == "going") null else "going", helping && status != "going") }
            ColorChip(null, C.amber, Modifier.weight(1f), icon = Icons.Default.QuestionMark, selected = status == "maybe") { set(if (status == "maybe") null else "maybe", helping && status != "maybe") }
            ColorChip(null, C.red, Modifier.weight(1f), icon = Icons.Default.Close, selected = status == "declined") { set(if (status == "declined") null else "declined", false) }
        }
    }
}

/** Detail als Sheet: voller Text, Foto, Zusagen — Ersteller und Admins sehen Helfer und Zusagen mit Namen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventDetailSheet(e: EventInfo, helpers: Int?, onSignIn: () -> Unit = {}, onDismiss: () -> Unit) {
    var editing by remember { mutableStateOf(false) }
    var people by remember { mutableStateOf<List<Participation>?>(null) }
    val showsPeople = canEdit(e)
    LaunchedEffect(e.id, Changes.version) { if (showsPeople) people = runCatching { CommunityApi.participations(e.id) }.getOrNull() }
    if (editing && e.communityId != null) {
        EventEditorSheet(communityId = e.communityId, existing = e, onDismiss = { editing = false; onDismiss() })
        return
    }
    val going = MyParticipation.byEvent[e.id]?.status == "going"
    val shareContext = LocalContext.current
    val shareScope = rememberCoroutineScope()
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader("Termin", leading = if (showsPeople && e.communityId != null) "Bearbeiten" to { editing = true } else null, trailing = "Fertig" to onDismiss)
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                Column(Modifier.cardSurface().goingOutline(going)) {
                    e.imageUrl?.let { EventPhoto(it, 220.dp) }
                    EventBody(e, helpers, compact = false, onSignIn = onSignIn)
                }
                ColorChip("Teilen", C.ink, Modifier.fillMaxWidth().padding(top = Spacing), icon = Icons.Default.Share) {
                    shareScope.launch { EventShare.share(shareContext, e) }
                }
            }
            if (showsPeople) {
                val list = people.orEmpty()
                val loading = people == null
                val helping = list.filter { it.helping && it.status != "declined" }
                val yes = list.filter { it.status == "going" }; val maybe = list.filter { it.status == "maybe" }
                if (e.helpersNeeded > 0) {
                    item { SectionHeader("Helfer ${helping.size}/${e.helpersNeeded}", Icons.Default.VolunteerActivism) }
                    if (helping.isEmpty()) item { InfoCard(if (loading) "Lade …" else "Noch niemand eingetragen.") }
                    items(helping.size) { i -> PersonRow(helping[i], C.heather) }
                }
                item { SectionHeader("Zusagen ${yes.size}" + if (maybe.isEmpty()) "" else " · Vielleicht ${maybe.size}", Icons.Default.CheckCircle) }
                if (yes.isEmpty() && maybe.isEmpty()) item { InfoCard(if (loading) "Lade …" else "Noch keine Zusagen.") }
                items(yes.size) { i -> PersonRow(yes[i], C.green) }
                items(maybe.size) { i -> PersonRow(maybe[i], C.amber) }
            }
        }
    }
}

@Composable
private fun PersonRow(p: Participation, color: Color) {
    RowCard {
        PersonAvatar(p.profile?.avatar, p.profile?.displayName ?: "Mitglied", color)
        Text(p.profile?.displayName ?: "Mitglied", fontWeight = FontWeight.SemiBold, color = C.text, modifier = Modifier.weight(1f))
        if (p.helping) Pill("Helfer", C.heather)
        if (p.status == "maybe") Pill("vielleicht", C.amber)
    }
}

// MARK: Editor

fun jpeg(context: android.content.Context, uri: Uri, maxSide: Int = 1600): ByteArray? = runCatching {
    val bmp = context.contentResolver.openInputStream(uri)!!.use { BitmapFactory.decodeStream(it) }
    val scale = minOf(1f, maxSide.toFloat() / maxOf(bmp.width, bmp.height))
    val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
    ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
}.getOrNull()

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventEditorSheet(communityId: String, existing: EventInfo?, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val start0 = existing?.starts?.withZoneSameInstant(Town.zone) ?: Town.now().plusHours(1).withMinute(0).withSecond(0).withNano(0) // nächste volle Stunde
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var location by remember { mutableStateOf(existing?.location ?: "") }
    var day by remember { mutableStateOf(start0.toLocalDate()) }
    var time by remember { mutableStateOf(start0.toLocalTime()) }
    var hasEnd by remember { mutableStateOf(existing?.ends != null) }
    var endTime by remember { mutableStateOf(existing?.ends?.withZoneSameInstant(Town.zone)?.toLocalTime() ?: start0.toLocalTime().plusHours(1)) }
    var helpers by remember { mutableIntStateOf(existing?.helpersNeeded ?: 0) }
    var isPublic by remember { mutableStateOf(existing?.isPublic ?: false) }
    // Foto beim Öffnen: wird nach dem Sichern gelöscht, wenn ersetzt (Standardbilder nie).
    val originalPath = remember { existing?.imageUrl?.substringAfter("/event-photos/") }
    var imagePath by remember { mutableStateOf(originalPath) }
    var newImage by remember { mutableStateOf<ByteArray?>(null) }
    var headerImages by remember { mutableStateOf<List<HeaderImage>>(emptyList()) }
    LaunchedEffect(communityId) { headerImages = runCatching { CommunityApi.headerImages(communityId) }.getOrDefault(emptyList()) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var picker by remember { mutableStateOf<String?>(null) }
    var confirmCancel by remember { mutableStateOf(false) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let { newImage = jpeg(context, it) } }

    fun save() = scope.launch {
        val user = Session.userId ?: return@launch
        saving = true; error = null
        runCatching {
            val path = newImage?.let { CommunityApi.uploadPhoto("event-photos", communityId, it) } ?: imagePath
            val starts = ZonedDateTime.of(day, time, Town.zone)
            var ends = if (hasEnd) ZonedDateTime.of(day, endTime, Town.zone) else null
            if (ends != null && !ends.isAfter(starts)) ends = ends.plusDays(1)
            val draft = EventDraft(communityId, title.trim(), description.trim(), starts.toOffsetDateTime().toString(), ends?.toOffsetDateTime()?.toString(),
                location.trim().ifBlank { null }, path, helpers, if (isPublic) "public" else "members", existing?.createdBy ?: user)
            if (existing == null) CommunityApi.createEvent(draft) else CommunityApi.updateEvent(existing.id, draft)
            if (originalPath != null && originalPath != path) CommunityApi.deletePhoto("event-photos", originalPath)
        }.onSuccess { Changes.bump(); onDismiss() }.onFailure { error = it.message }
        saving = false
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader(if (existing == null) "Neuer Termin" else "Termin bearbeiten", leading = "Abbrechen" to onDismiss,
            trailing = (if (saving) "…" else "Sichern") to { if (title.isNotBlank() && !saving) save() })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            // Foto: oben gerundet wie die Karte, unten gerade.
            val shown: Any? = newImage ?: imagePath?.let { Backend.photoUrl(it) }
            Column(Modifier.fillMaxWidth().clip(CardShape).background(C.surface)) {
                if (shown != null) AsyncImage(shown, null, Modifier.fillMaxWidth().height(170.dp).clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                if (headerImages.isNotEmpty()) {
                    Text("Standardbild", fontWeight = FontWeight.SemiBold, fontSize = 14.sp, color = C.text, modifier = Modifier.padding(start = 12.dp, top = 12.dp))
                    HeaderImageRow(headerImages, if (newImage == null) imagePath else null) { imagePath = it.path; newImage = null }
                }
                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ColorChip(if (shown == null) "Eigenes Foto" else "Eigenes Foto ändern", C.teal, icon = Icons.Default.Photo) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                    if (shown != null) ColorChip("Entfernen", C.red, icon = Icons.Default.Delete) { newImage = null; imagePath = null }
                }
            }
            StedeCard {
                OutlinedTextField(title, { title = it }, label = { Text("Titel") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(location, { location = it }, label = { Text("Ort") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                OutlinedTextField(description, { description = it }, label = { Text("Beschreibung") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
            }
            StedeCard {
                FormRow("Datum", day.format(Town.dayFull)) { picker = "day" }
                FormRow("Beginn", time.format(Town.hm)) { picker = "start" }
                Row(verticalAlignment = Alignment.CenterVertically) { Text("Ende", color = C.text, modifier = Modifier.weight(1f)); Switch(hasEnd, { hasEnd = it }) }
                if (hasEnd) FormRow("Endet um", endTime.format(Town.hm)) { picker = "end" }
            }
            StedeCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text("Helfer gesucht", color = C.text); Text(if (helpers == 0) "keine" else "$helpers Personen", color = C.secondary, fontSize = 13.sp) }
                    IconButton(onClick = { if (helpers > 0) helpers-- }) { Icon(Icons.Default.Remove, "Weniger", tint = C.ink) }
                    IconButton(onClick = { helpers++ }) { Icon(Icons.Default.Add, "Mehr", tint = C.ink) }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text("Öffentlich", color = C.text); Text("Erscheint im Stadtkalender für alle", color = C.secondary, fontSize = 13.sp) }
                    Switch(isPublic, { isPublic = it })
                }
            }
            error?.let { Text(it, color = C.red) }
            if (existing != null && !existing.isCancelled) ColorChip("Termin absagen", C.red, Modifier.fillMaxWidth(), icon = Icons.Default.EventBusy) { confirmCancel = true }
        }
    }
    when (picker) {
        "day" -> DatePickDialog(day, { picker = null }) { day = it; picker = null }
        "start" -> TimePickDialog(time, { picker = null }) { time = it; if (endTime <= it) endTime = it.plusHours(1); picker = null }
        "end" -> TimePickDialog(endTime, { picker = null }) { endTime = it; picker = null }
    }
    if (confirmCancel && existing != null) AlertDialog(onDismissRequest = { confirmCancel = false },
        title = { Text("Termin absagen?") }, text = { Text("Der Termin bleibt sichtbar, ist aber als abgesagt markiert.") },
        confirmButton = { TextButton({ confirmCancel = false; scope.launch { runCatching { CommunityApi.cancelEvent(existing.id) }; Changes.bump(); onDismiss() } }) { Text("Absagen", color = C.red) } },
        dismissButton = { TextButton({ confirmCancel = false }) { Text("Zurück") } })
}

@Composable
fun FormRow(label: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onClick() }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = C.text, modifier = Modifier.weight(1f)); Text(value, color = C.ink, fontWeight = FontWeight.SemiBold)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DatePickDialog(day: LocalDate, onDismiss: () -> Unit, onPick: (LocalDate) -> Unit) {
    val state = rememberDatePickerState(initialSelectedDateMillis = day.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli())
    DatePickerDialog(onDismissRequest = onDismiss, confirmButton = {
        TextButton({ state.selectedDateMillis?.let { onPick(java.time.Instant.ofEpochMilli(it).atZone(java.time.ZoneOffset.UTC).toLocalDate()) } ?: onDismiss() }) { Text("OK") }
    }, dismissButton = { TextButton(onDismiss) { Text("Abbrechen") } }) { DatePicker(state) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimePickDialog(time: LocalTime, onDismiss: () -> Unit, onPick: (LocalTime) -> Unit) {
    val state = rememberTimePickerState(time.hour, time.minute, is24Hour = true)
    AlertDialog(onDismissRequest = onDismiss, confirmButton = { TextButton({ onPick(LocalTime.of(state.hour, state.minute)) }) { Text("OK") } },
        dismissButton = { TextButton(onDismiss) { Text("Abbrechen") } }, text = { TimePicker(state) })
}

/** Zugesagte Termine dezent markieren: weiße Karte, feiner grüner Rahmen statt Türkis-Fläche. */
@Composable
fun Modifier.goingOutline(isGoing: Boolean): Modifier =
    if (isGoing) border(1.5.dp, C.green.copy(alpha = 0.55f), CardShape) else this

/** Standardbilder der Community als waagerechte Reihe; antippen setzt das Kopfbild. */
@Composable
fun HeaderImageRow(images: List<HeaderImage>, selectedPath: String?, onSelect: (HeaderImage) -> Unit) {
    androidx.compose.foundation.lazy.LazyRow(contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        items(images.size) { i ->
            val img = images[i]
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.width(96.dp).clickable { onSelect(img) }) {
                AsyncImage(img.url, img.label, Modifier.size(96.dp, 64.dp).clip(ChipShape)
                    .then(if (img.path == selectedPath) Modifier.border(3.dp, C.ink, ChipShape) else Modifier),
                    contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                Text(img.label, fontSize = 11.sp, color = C.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

/** Ort auf Terminkarten (Stadt und Gruppen): grau, einzeilig, linksbündig unter der Kopfzeile. */
@Composable
fun LocationLine(text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Default.Place, null, tint = C.secondary, modifier = Modifier.size(13.dp))
        Text(text, color = C.secondary, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
