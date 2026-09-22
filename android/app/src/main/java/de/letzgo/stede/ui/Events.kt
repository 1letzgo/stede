package de.letzgo.stede.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
fun canEdit(e: EventInfo) = Session.userId != null && (e.createdBy == Session.userId || (e.communityId != null && e.communityId in Session.adminCommunityIds))

/** Termin-Karte wie EventCard in iOS: Foto oben, Logo, Zeit- und Helfer-Pill, Schloss wenn intern, Teilnahmezeile. */
@Composable
fun EventCard(e: EventInfo, helpers: Int?, onOpen: () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(CardShape).background(C.surface).clickable { onOpen() }) {
        e.imageUrl?.let { EventPhoto(it, 150.dp) }
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                CommunityAvatar(e.logoUrl, e.community)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(e.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = if (e.isCancelled) C.secondary else C.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Pill(if (e.isCancelled) "Abgesagt" else timeLabel(e), if (e.isCancelled) C.red else C.teal)
                        if (e.helpersNeeded > 0 && !e.isCancelled) Pill("Helfer ${helpers ?: 0}/${e.helpersNeeded}", C.amber)
                    }
                    e.location?.takeIf { it.isNotBlank() }?.let { Text(it, color = C.secondary, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                }
                if (!e.isPublic) Icon(Icons.Default.Lock, "Intern", tint = C.secondary, modifier = Modifier.size(16.dp))
            }
            if (!e.isCancelled && Session.signedIn) ParticipationRow(e, helpers)
        }
    }
}

/** Ich komme / Vielleicht / Absagen (+ Helfen) — nur Symbole, gleich breit, gleich hoch. */
@Composable
fun ParticipationRow(e: EventInfo, helpers: Int?, onChange: () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    val mine = MyParticipation.byEvent[e.id]
    val helping = mine?.helping == true
    val showHelp = e.helpersNeeded > 0 && (helping || (helpers ?: 0) < e.helpersNeeded)
    fun set(status: String?, help: Boolean) = scope.launch { runCatching { MyParticipation.set(e.id, status, help) }; Changes.bump(); onChange() }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        data class Opt(val status: String, val icon: ImageVector, val label: String, val color: Color)
        listOf(Opt("going", Icons.Default.Check, "Ich komme", C.green), Opt("maybe", Icons.Default.QuestionMark, "Vielleicht", C.amber), Opt("declined", Icons.Default.Close, "Absagen", C.red)).forEach { o ->
            ColorChip(null, o.color, Modifier.weight(1f), icon = o.icon, selected = mine?.status == o.status) {
                if (mine?.status == o.status) set(null, false) else set(o.status, helping && o.status != "declined")
            }
        }
        if (showHelp) ColorChip(null, C.teal, Modifier.weight(1f), icon = Icons.Default.VolunteerActivism, selected = helping) {
            set(if (mine == null || mine.status == "declined") "going" else mine.status, !helping)
        }
    }
}

/** Detail eines Community-Termins: Bearbeiten links (wenn erlaubt), Fertig rechts; Ersteller sieht Teilnehmer und Helfer. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventDetailSheet(e: EventInfo, helpers: Int?, onDismiss: () -> Unit) {
    var editing by remember { mutableStateOf(false) }
    var people by remember { mutableStateOf<List<Participation>?>(null) }
    val showsPeople = canEdit(e)
    LaunchedEffect(e.id, Changes.version) { if (showsPeople) people = runCatching { CommunityApi.participations(e.id) }.getOrNull() }
    if (editing) {
        EventEditorSheet(communityId = e.communityId ?: return, existing = e, onDismiss = { editing = false; onDismiss() })
        return
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand) {
        SheetHeader(e.title, leading = if (showsPeople && e.communityId != null) "Bearbeiten" to { editing = true } else null, trailing = "Fertig" to onDismiss)
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                Column(Modifier.fillMaxWidth().clip(CardShape).background(C.surface)) {
                    e.imageUrl?.let { EventPhoto(it, 200.dp) }
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                            CommunityAvatar(e.logoUrl, e.community)
                            Text(e.community, color = C.secondary, modifier = Modifier.weight(1f))
                            if (!e.isPublic) Icon(Icons.Default.Lock, "Intern", tint = C.secondary, modifier = Modifier.size(16.dp))
                        }
                        Text(e.title, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.text)
                        InfoLine(Icons.Default.CalendarMonth, "${e.starts.withZoneSameInstant(Town.zone).format(Town.dayLong)} · ${timeLabel(e)}")
                        e.location?.takeIf { it.isNotBlank() }?.let { InfoLine(Icons.Default.Place, it) }
                        if (e.helpersNeeded > 0) InfoLine(Icons.Default.VolunteerActivism, "${helpers ?: 0} von ${e.helpersNeeded} Helfern")
                        if (e.isCancelled) Pill("Abgesagt", C.red)
                        if (e.description.isNotBlank()) Text(e.description, color = C.text)
                        if (!e.isCancelled && Session.signedIn) ParticipationRow(e, helpers)
                    }
                }
            }
            if (showsPeople) {
                val list = people ?: emptyList()
                listOf("going" to "Zusagen", "maybe" to "Vielleicht", "declined" to "Absagen").forEach { (status, title) ->
                    val group = list.filter { it.status == status }
                    if (group.isNotEmpty()) {
                        item { SectionHeader("$title (${group.size})") }
                        item { StedeCard { group.forEach { p -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 4.dp)) {
                            Text(p.profile?.displayName ?: "Mitglied", color = C.text, modifier = Modifier.weight(1f))
                            if (p.helping) Pill("hilft", C.teal)
                        } } } }
                    }
                }
                if (people != null && list.isEmpty()) item { InfoCard("Noch keine Rückmeldungen.") }
            }
        }
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
    val start0 = existing?.starts?.withZoneSameInstant(Town.zone) ?: Town.now().plusDays(1).withHour(18).withMinute(0).withSecond(0).withNano(0)
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var description by remember { mutableStateOf(existing?.description ?: "") }
    var location by remember { mutableStateOf(existing?.location ?: "") }
    var day by remember { mutableStateOf(start0.toLocalDate()) }
    var time by remember { mutableStateOf(start0.toLocalTime()) }
    var hasEnd by remember { mutableStateOf(existing?.ends != null) }
    var endTime by remember { mutableStateOf(existing?.ends?.withZoneSameInstant(Town.zone)?.toLocalTime() ?: start0.toLocalTime().plusHours(2)) }
    var helpers by remember { mutableIntStateOf(existing?.helpersNeeded ?: 0) }
    var isPublic by remember { mutableStateOf(existing?.isPublic ?: false) }
    var imagePath by remember { mutableStateOf(existing?.imageUrl?.substringAfter("/event-photos/")) }
    var newImage by remember { mutableStateOf<ByteArray?>(null) }
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
        }.onSuccess { Changes.bump(); onDismiss() }.onFailure { error = it.message }
        saving = false
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand) {
        SheetHeader(if (existing == null) "Neuer Termin" else "Termin bearbeiten", leading = "Abbrechen" to onDismiss,
            trailing = (if (saving) "…" else "Sichern") to { if (title.isNotBlank() && !saving) save() })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            // Foto: oben gerundet wie die Karte, unten gerade.
            val shown: Any? = newImage ?: imagePath?.let { Backend.photoUrl(it) }
            Column(Modifier.fillMaxWidth().clip(CardShape).background(C.surface)) {
                if (shown != null) AsyncImage(shown, null, Modifier.fillMaxWidth().height(170.dp).clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ColorChip(if (shown == null) "Foto hinzufügen" else "Foto ändern", C.teal, icon = Icons.Default.Photo) { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
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
        "start" -> TimePickDialog(time, { picker = null }) { time = it; if (endTime <= it) endTime = it.plusHours(2); picker = null }
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
