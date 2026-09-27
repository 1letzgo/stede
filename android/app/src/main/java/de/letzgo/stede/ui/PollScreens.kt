package de.letzgo.stede.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime

/** Umfragen einer Gruppe samt Stimmen; lädt beim ersten Öffnen des Reiters „Umfragen“ — wie PollsModel in iOS. */
class PollsModel(private val communityId: String) {
    var polls by mutableStateOf<List<CommunityPoll>?>(null); private set
    var votes by mutableStateOf<Map<String, List<PollVote>>>(emptyMap()); private set
    var lastError by mutableStateOf<String?>(null)

    suspend fun load() {
        runCatching {
            val list = PollApi.polls(communityId)
            list to PollApi.votes(list.map { it.id })
        }.onSuccess { (list, all) ->
            votes = all.groupBy { it.pollId }; polls = list; lastError = null
        }.onFailure {
            if (polls == null) polls = emptyList()
            lastError = it.message
        }
    }

    /** Antwort an- oder abwählen; bei Einfachauswahl ersetzt der Server die alte Stimme. */
    suspend fun toggle(option: PollOption, poll: CommunityPoll, userId: String) {
        val mine = votes[poll.id].orEmpty().any { it.optionId == option.id && it.userId == userId }
        runCatching { if (mine) PollApi.unvote(option.id, userId) else PollApi.vote(poll.id, option.id, userId) }
            .onSuccess { load() }.onFailure { lastError = it.message }
    }

    suspend fun create(draft: PollDraft, userId: String): Boolean =
        runCatching { PollApi.create(draft, communityId, userId) }.onFailure { lastError = it.message }.isSuccess.also { if (it) load() }

    suspend fun close(poll: CommunityPoll) { runCatching { PollApi.close(poll.id) }.onFailure { lastError = it.message }; load() }
    suspend fun delete(poll: CommunityPoll) { runCatching { PollApi.delete(poll.id) }.onFailure { lastError = it.message }; load() }
}

/** Zeitpunkte einer Umfrage in Ortszeit: „Sa., 3. Okt. · 19:00“. */
object PollFormat {
    private val slotDay = Town.fmt("EE, d. MMM")
    private val deadline = Town.fmt("d. MMM yyyy, HH:mm")
    fun slot(t: ZonedDateTime): String { val z = t.withZoneSameInstant(Town.zone); return "${z.format(slotDay)} · ${z.format(Town.hm)}" }
    fun deadline(t: ZonedDateTime): String = t.withZoneSameInstant(Town.zone).format(deadline)
    fun label(option: PollOption, poll: CommunityPoll) = if (poll.isDate) Town.parse(option.startsAt)?.let { slot(it) } ?: option.label else option.label
}

/** Eine Umfrage als Karte: Frage, Status, Antworten mit Balken und Namen; Tippen stimmt ab. */
@Composable
fun PollCard(poll: CommunityPoll, votes: List<PollVote>, userId: String?, isAdmin: Boolean, onToggle: (PollOption) -> Unit, onClose: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val isOpen = poll.isOpen()
    // Abstimmende Personen (nicht Stimmen) — Basis für die Anteile bei Mehrfachauswahl.
    val voterCount = votes.map { it.userId }.toSet().size
    val options = poll.options
    val counts = options.associate { o -> o.id to votes.count { it.optionId == o.id } }
    val maxVotes = counts.values.maxOrNull() ?: 0
    StedeCard {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            IconChip(if (poll.isDate) Icons.Default.EditCalendar else Icons.Default.BarChart, C.heather)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(poll.question, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                val parts = buildList {
                    if (poll.isDate) add("Terminfindung")
                    if (poll.multiple) add("Mehrfachauswahl")
                    if (!isOpen) add("Beendet") else poll.closes?.let { add("bis ${PollFormat.deadline(it)}") }
                }
                Text(parts.ifEmpty { listOf("Eine Antwort") }.joinToString(" · "), fontSize = 12.sp, color = if (isOpen) C.secondary else C.red)
            }
            if (isAdmin) Box {
                IconButton(onClick = { menu = true }, modifier = Modifier.size(32.dp)) { Icon(Icons.Default.MoreHoriz, "Umfrage verwalten", tint = C.ink) }
                DropdownMenu(menu, { menu = false }) {
                    if (isOpen) DropdownMenuItem({ Text("Umfrage beenden") }, { menu = false; onClose() }, leadingIcon = { Icon(Icons.Default.Lock, null) })
                    DropdownMenuItem({ Text("Löschen", color = C.red) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Default.Delete, null, tint = C.red) })
                }
            }
        }
        poll.description?.takeIf { it.isNotBlank() }?.let { Text(it, color = C.secondary, fontSize = 15.sp, modifier = Modifier.padding(top = 10.dp)) }
        Column(Modifier.padding(vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            options.forEach { option ->
                val here = counts[option.id] ?: 0
                val share = if (voterCount > 0) here.toFloat() / voterCount else 0f
                val mine = votes.any { it.optionId == option.id && it.userId == userId }
                val leading = !isOpen && here > 0 && here == maxVotes
                val names = votes.filter { it.optionId == option.id }.mapNotNull { it.profile?.displayName }.sorted()
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.sand)
                    .clickable(enabled = isOpen && userId != null) { onToggle(option) }.padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        val icon = when {
                            poll.multiple && mine -> Icons.Default.CheckBox
                            poll.multiple -> Icons.Default.CheckBoxOutlineBlank
                            mine -> Icons.Default.CheckCircle
                            else -> Icons.Default.RadioButtonUnchecked
                        }
                        Icon(icon, if (mine) "Gewählt" else null, tint = if (mine) C.heather else C.secondary, modifier = Modifier.size(22.dp))
                        Text(PollFormat.label(option, poll), color = C.text, fontWeight = if (leading) FontWeight.SemiBold else FontWeight.Normal, modifier = Modifier.weight(1f))
                        Text("$here", color = C.secondary, fontSize = 15.sp)
                    }
                    Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)).background(C.heather.copy(alpha = 0.12f))) {
                        if (share > 0f) Box(Modifier.widthIn(min = 6.dp).fillMaxWidth(share).fillMaxHeight().clip(RoundedCornerShape(50))
                            .background(C.heather.copy(alpha = if (mine || leading) 0.8f else 0.45f)))
                    }
                    if (names.isNotEmpty()) Text(names.joinToString(", "), fontSize = 12.sp, color = C.secondary, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Text(if (voterCount == 1) "1 Person hat abgestimmt" else "$voterCount Personen haben abgestimmt", fontSize = 12.sp, color = C.secondary)
    }
    if (confirmDelete) AlertDialog(onDismissRequest = { confirmDelete = false }, title = { Text("Umfrage löschen?") },
        text = { Text("Frage, Antworten und alle Stimmen werden entfernt.") },
        confirmButton = { TextButton({ confirmDelete = false; onDelete() }) { Text("Löschen", color = C.red) } },
        dismissButton = { TextButton({ confirmDelete = false }) { Text("Abbrechen") } })
}

/** Neue Umfrage: Frage, Art (Antworten / Terminfindung), Möglichkeiten, Mehrfachauswahl, Enddatum — wie PollEditorView in iOS. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PollEditorSheet(onDismiss: () -> Unit, onSave: suspend (PollDraft) -> Boolean) {
    val scope = rememberCoroutineScope()
    val nextHour = remember { Town.now().plusHours(1).withMinute(0).withSecond(0).withNano(0) } // nächste volle Stunde
    var question by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var isDate by remember { mutableStateOf(false) }
    var multiple by remember { mutableStateOf(false) }
    var hasDeadline by remember { mutableStateOf(false) }
    var closesAt by remember { mutableStateOf(nextHour.plusDays(7)) }
    val texts = remember { mutableStateListOf("", "") }
    val slots = remember { mutableStateListOf(nextHour, nextHour.plusDays(1)) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    // Offener Picker: Index des Vorschlags (-1 = Enddatum) und ob Datum oder Uhrzeit.
    var picker by remember { mutableStateOf<Pair<Int, Boolean>?>(null) }
    val cleanTexts = texts.map { it.trim() }.filter { it.isNotEmpty() }
    val canSave = question.isNotBlank() && (if (isDate) slots.size >= 2 else cleanTexts.size >= 2) && !saving

    fun save() {
        saving = true; error = null
        val options = if (isDate) slots.sorted().map { "" to it } else cleanTexts.map { it to null }
        val draft = PollDraft(question.trim(), description.trim(), if (isDate) "date" else "text", multiple, if (hasDeadline) closesAt else null, options)
        scope.launch {
            if (onSave(draft)) onDismiss() else error = "Die Umfrage konnte nicht angelegt werden."
            saving = false
        }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader("Neue Umfrage", leading = "Abbrechen" to onDismiss, trailing = (if (saving) "…" else "Starten") to { if (canSave) save() })
        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            StedeCard {
                OutlinedTextField(question, { question = it.take(300) }, label = { Text("Frage") }, modifier = Modifier.fillMaxWidth(), maxLines = 3)
                OutlinedTextField(description, { description = it }, label = { Text("Beschreibung (optional)") }, modifier = Modifier.fillMaxWidth(), minLines = 2, maxLines = 5)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(false to "Antworten", true to "Terminfindung").forEach { (value, label) ->
                    SelectionChip(label, isDate == value, Modifier.weight(1f), compact = true) {
                        isDate = value
                        if (value) multiple = true // Terminfindung: alle passenden Termine markieren
                    }
                }
            }
            if (!isDate) {
                SectionHeader("Antworten")
                StedeCard {
                    texts.forEachIndexed { index, text ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(text, { texts[index] = it }, label = { Text("Antwort ${index + 1}") }, singleLine = true, modifier = Modifier.weight(1f))
                            if (texts.size > 2) IconButton(onClick = { texts.removeAt(index) }) { Icon(Icons.Default.RemoveCircleOutline, "Entfernen", tint = C.red) }
                        }
                    }
                    ColorChip("Antwort hinzufügen", C.teal, Modifier.padding(top = 10.dp), icon = Icons.Default.Add) { texts.add("") }
                }
            } else {
                SectionHeader("Terminvorschläge")
                StedeCard {
                    slots.forEachIndexed { index, slot ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Vorschlag ${index + 1}", color = C.text, modifier = Modifier.weight(1f))
                            Text(slot.format(Town.fmt("EE, d. MMM yyyy")), color = C.ink, fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.clickable { picker = index to true }.padding(vertical = 10.dp, horizontal = 6.dp))
                            Text(slot.format(Town.hm), color = C.ink, fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.clickable { picker = index to false }.padding(vertical = 10.dp, horizontal = 6.dp))
                            if (slots.size > 2) IconButton(onClick = { slots.removeAt(index) }, modifier = Modifier.size(36.dp)) { Icon(Icons.Default.RemoveCircleOutline, "Entfernen", tint = C.red) }
                        }
                    }
                    ColorChip("Termin hinzufügen", C.teal, Modifier.padding(top = 10.dp), icon = Icons.Default.Add) { slots.add((slots.lastOrNull() ?: nextHour).plusDays(1)) }
                }
                Text("Mitglieder markieren alle Termine, an denen sie können.", color = C.secondary, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
            }
            StedeCard {
                Row(verticalAlignment = Alignment.CenterVertically) { Text("Mehrfachauswahl", color = C.text, modifier = Modifier.weight(1f)); Switch(multiple, { multiple = it }) }
                Row(verticalAlignment = Alignment.CenterVertically) { Text("Enddatum", color = C.text, modifier = Modifier.weight(1f)); Switch(hasDeadline, { hasDeadline = it }) }
                if (hasDeadline) {
                    FormRow("Endet am", closesAt.format(Town.dayFull)) { picker = -1 to true }
                    FormRow("Um", closesAt.format(Town.hm)) { picker = -1 to false }
                }
            }
            Text("Alle Mitglieder sehen, wer wofür gestimmt hat.", color = C.secondary, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
            error?.let { Text(it, color = C.red) }
        }
    }
    picker?.let { (index, isDay) ->
        val current = if (index < 0) closesAt else slots.getOrNull(index) ?: return@let
        fun set(value: ZonedDateTime) { if (index < 0) closesAt = value else slots[index] = value; picker = null }
        if (isDay) DatePickDialog(current.toLocalDate(), { picker = null }) { day: LocalDate -> set(ZonedDateTime.of(day, current.toLocalTime(), Town.zone)) }
        else TimePickDialog(current.toLocalTime(), { picker = null }) { time: LocalTime -> set(ZonedDateTime.of(current.toLocalDate(), time, Town.zone)) }
    }
}
