package de.letzgo.stede.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.Screen
import de.letzgo.stede.data.*
import kotlinx.coroutines.launch

// Politik — wie PoliticsView.swift in iOS: Sitzungen, Tagesordnungen und Vorlagen aus dem Ratsinfo.

private val monthTitle = Town.fmt("MMMM yyyy")

@Composable
fun CouncilSessionsScreen(open: (Screen) -> Unit, onBack: () -> Unit) {
    var sessions by remember { mutableStateOf(Council.cachedSessions()) }
    var error by remember { mutableStateOf<String?>(null) }
    var showsPast by remember { mutableStateOf(false) }
    var firstMonth by remember { mutableStateOf(Town.today().withDayOfMonth(1)) }
    var loadingEarlier by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        runCatching { Council.upcomingSessions() }.onSuccess { sessions = it; error = null }
            .onFailure { if (sessions == null) error = "Der Sitzungskalender konnte nicht geladen werden." }
    }
    val visible = sessions.orEmpty().filter { showsPast || !it.isOver }
    val nextId = sessions?.firstOrNull { !it.isOver }?.id

    Scaffold(topBar = { StedeTopBar("Sitzungen", onBack) }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                ColorChip(if (loadingEarlier) "Lade …" else "Frühere Sitzungen", C.ink, icon = Icons.Default.History, enabled = !loadingEarlier) {
                    // Erst die vergangenen des laufenden Monats zeigen, danach je einen Monat zurück.
                    if (!showsPast) { showsPast = true; return@ColorChip }
                    scope.launch {
                        loadingEarlier = true
                        val month = firstMonth.minusMonths(1)
                        runCatching { Council.sessions(month.year, month.monthValue) }.onSuccess { earlier ->
                            sessions = (earlier + sessions.orEmpty()).distinctBy { it.id }.sortedBy { it.start }
                            firstMonth = month
                        }
                        loadingEarlier = false
                    }
                }
            }
            when {
                sessions == null && error == null -> item { Loading() }
                error != null -> item { InfoCard(error!!) }
                visible.isEmpty() -> item { InfoCard("In den nächsten Wochen sind keine Sitzungen angesetzt.") }
            }
            visible.groupBy { it.startTime.withDayOfMonth(1).toLocalDate() }.forEach { (month, list) ->
                item(key = "m$month") { SectionHeader(month.format(monthTitle), Icons.Default.CalendarMonth) }
                items(list, key = { it.id }) { s -> CouncilSessionCard(s, s.id == nextId) { open(Screen.CouncilSessionDetail(s)) } }
            }
            item { SourceFooter("Sitzungskalender · ${Council.host} · Angaben ohne Gewähr") }
        }
    }
}

@Composable
fun CouncilSessionCard(s: CouncilSession, isNext: Boolean, onClick: () -> Unit) {
    StedeCard(Modifier.alpha(if (s.isOver) 0.6f else 1f), highlighted = isNext, onClick = onClick) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconChip(Icons.Default.Groups, C.teal)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(s.committee, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (isNext) Pill("Nächste", C.teal)
                    if (!s.hasAgenda) Pill(if (s.isOver) "ohne Tagesordnung" else "Tagesordnung folgt", C.mudflat)
                }
            }
        }
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            InfoLine(Icons.Default.CalendarMonth, s.startTime.format(Town.dayLong) + if (s.hasTime) ", " + timeRange(s) else "")
            s.room?.let { InfoLine(Icons.Default.Place, it) }
        }
    }
}

private fun timeRange(s: CouncilSession) =
    s.endTime?.let { "${s.startTime.format(Town.hm)}–${it.format(Town.hm)} Uhr" } ?: "${s.startTime.format(Town.hm)} Uhr"

@Composable
fun CouncilSessionScreen(session: CouncilSession, open: (Screen) -> Unit, onBack: () -> Unit) {
    var agenda by remember { mutableStateOf<CouncilAgenda?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val openUrl = rememberOpenUrl()
    val documents = rememberDocumentOpener()
    LaunchedEffect(session.id) {
        if (session.hasAgenda) runCatching { Council.agenda(session.id) }.onSuccess { agenda = it }.onFailure { error = "Die Tagesordnung konnte nicht geladen werden." }
    }
    Scaffold(topBar = { StedeTopBar(session.committee, onBack) }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                StedeCard {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        IconChip(Icons.Default.Groups, C.teal)
                        Text(session.title, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                    }
                    Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        InfoLine(Icons.Default.CalendarMonth, session.startTime.format(Town.fmt("EEEE, d. MMMM yyyy")))
                        if (session.hasTime) InfoLine(Icons.Default.Schedule, agenda?.time?.takeIf { it.isNotEmpty() }?.let { "$it Uhr" } ?: timeRange(session))
                        session.room?.let { InfoLine(Icons.Default.Place, it) }
                        agenda?.place?.takeIf { it.isNotEmpty() && it != session.room }?.let { InfoLine(Icons.Default.Business, it) }
                    }
                    ActionChips(agenda?.documents.orEmpty(), null, documents) {
                        if (session.hasAgenda) ActionChip("Im Ratsinfo öffnen", Icons.Default.Language) { openUrl(Council.agendaUrl(session.id)) }
                    }
                }
            }
            when {
                !session.hasAgenda -> item { InfoCard(if (session.isOver) "Zu dieser Sitzung ist keine Tagesordnung veröffentlicht."
                    else "Die Tagesordnung ist noch nicht veröffentlicht. Sie erscheint in der Regel etwa eine Woche vor der Sitzung.") }
                error != null -> item { InfoCard(error!!) }
                agenda == null -> item { Loading() }
                agenda!!.items.isEmpty() -> item { InfoCard("Die Tagesordnung enthält keine Punkte.") }
                else -> {
                    item { SectionHeader("Tagesordnung", Icons.Default.FormatListNumbered) }
                    itemsIndexed(agenda!!.items) { _, item ->
                        AgendaRow(item, onClick = item.paperId?.let { id -> { open(Screen.CouncilPaperDetail(id, item.paperNumber.orEmpty())) } })
                    }
                }
            }
            item { SourceFooter("Ratsinformationssystem · ${Council.host}") }
        }
    }
}

@Composable
private fun AgendaRow(item: CouncilAgendaItem, onClick: (() -> Unit)?) {
    StedeCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            // TOP-Nummer in einer Kachel wie die Symbole der übrigen Karten.
            Box(Modifier.size(38.dp).background((if (item.isPublic) C.ink else C.mudflat).copy(alpha = 0.14f), ChipShape), contentAlignment = Alignment.Center) {
                Text(item.number.removePrefix("Ö ").trim(), fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = if (item.isPublic) C.ink else C.mudflat)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(item.title, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, color = C.text)
                val pills = listOfNotNull(item.paperNumber, item.result, if (!item.isPublic) "nicht öffentlich" else null)
                if (pills.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    item.paperNumber?.let { Pill(it, C.amber) }
                    item.result?.let { Pill(it, resultColor(it)) }
                    if (!item.isPublic) Pill("nicht öffentlich", C.mudflat)
                }
            }
        }
    }
}

@Composable
private fun resultColor(result: String): Color = when {
    "abgelehnt" in result.lowercase() -> C.red
    "beschlossen" in result.lowercase() || "zugestimmt" in result.lowercase() -> C.green
    else -> C.mudflat
}

@Composable
fun CouncilPapersScreen(open: (Screen) -> Unit, onBack: () -> Unit) {
    var items by remember { mutableStateOf(Council.cachedPapers().orEmpty()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var hasNext by remember { mutableStateOf(false) }
    var total by remember { mutableStateOf<Int?>(null) }
    var query by remember { mutableStateOf("") }
    var shownQuery by remember { mutableStateOf("") }
    var loadingMore by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    suspend fun search(text: String) {
        loading = true; error = null
        if (text != shownQuery) items = emptyList()
        shownQuery = text
        runCatching { Council.papers(text) }.onSuccess { page ->
            if (shownQuery != text) return@onSuccess
            items = page.items; hasNext = page.hasNext; total = page.approximateTotal
            if (text.isBlank()) Council.savePapers(page.items)
        }.onFailure { if (items.isEmpty()) error = "Die Vorlagen konnten nicht geladen werden." }
        loading = false
    }
    LaunchedEffect(Unit) { search("") }

    Scaffold(topBar = { StedeTopBar("Vorlagen", onBack) }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                StedeCard(padding = 12.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Icon(Icons.Default.Search, null, tint = C.secondary, modifier = Modifier.padding(start = 4.dp))
                        StedeTextField(query, { query = it; if (it.isEmpty() && shownQuery.isNotEmpty()) scope.launch { search("") } },
                            "Betreff durchsuchen", Modifier.weight(1f),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = { scope.launch { search(query.trim()) } }))
                    }
                }
            }
            if (shownQuery.isEmpty()) total?.let { item { Text("Rund $it Vorlagen, die neuesten zuerst", color = C.secondary, fontSize = 13.sp) } }
            when {
                items.isEmpty() && loading -> item { Loading() }
                error != null -> item { InfoCard(error!!) }
                items.isEmpty() -> item { InfoCard(if (shownQuery.isEmpty()) "Keine Vorlagen gefunden." else "Keine Vorlage mit „$shownQuery“ im Betreff.") }
            }
            itemsIndexed(items, key = { _, p -> p.id }) { index, paper ->
                PaperCard(paper) { open(Screen.CouncilPaperDetail(paper.id, paper.number)) }
                // Nächste Seite, sobald eine der letzten Zeilen erscheint.
                if (index >= items.size - 5 && hasNext && !loadingMore) LaunchedEffect(items.size) {
                    loadingMore = true
                    val q = shownQuery
                    runCatching { Council.nextPapers() }.onSuccess { page ->
                        if (q == shownQuery) {
                            val known = items.map { it.id }.toSet()
                            items = items + page.items.filter { it.id !in known }; hasNext = page.hasNext
                        }
                    }
                    loadingMore = false
                }
            }
            if (loadingMore) item { Loading() }
            item { SourceFooter("Ratsinformationssystem · ${Council.host} · Angaben ohne Gewähr") }
        }
    }
}

@Composable
private fun PaperCard(p: CouncilPaper, onClick: () -> Unit) {
    StedeCard(onClick = onClick) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconChip(Icons.Default.Description, C.amber)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(p.subject, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text, maxLines = 4, overflow = TextOverflow.Ellipsis)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { Pill(p.number, C.amber); if (p.kind.isNotEmpty()) Pill(p.kind, C.ink) }
            }
        }
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (p.office.isNotEmpty()) InfoLine(Icons.Default.Business, p.office)
            InfoLine(Icons.Default.CalendarMonth, if (p.hasAttachments) "${p.date} · mit Anlagen" else p.date)
        }
    }
}

@Composable
fun CouncilPaperScreen(id: Int, number: String, onBack: () -> Unit) {
    var paper by remember { mutableStateOf<CouncilPaperDetail?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val documents = rememberDocumentOpener()
    LaunchedEffect(id) { runCatching { Council.paper(id) }.onSuccess { paper = it }.onFailure { error = "Die Vorlage konnte nicht geladen werden." } }
    Scaffold(topBar = { StedeTopBar(paper?.number?.ifEmpty { null } ?: number, onBack) }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            val p = paper
            when {
                error != null -> item { InfoCard(error!!) }
                p == null -> item { Loading() }
                else -> {
                    item {
                        StedeCard {
                            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                IconChip(Icons.Default.Description, C.amber)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    SelectionContainer { Text(p.subject, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text) }
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        if (p.kind.isNotEmpty()) Pill(p.kind, C.amber)
                                        if (p.status.isNotEmpty()) Pill(p.status, C.ink)
                                    }
                                }
                            }
                            Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                if (p.office.isNotEmpty()) InfoLine(Icons.Default.Business, p.office)
                                if (p.clerk.isNotEmpty()) InfoLine(Icons.Default.Person, p.clerk)
                            }
                            ActionChips(p.documents + p.attachments, p.id, documents)
                        }
                    }
                    if (p.consultations.isNotEmpty()) {
                        item { SectionHeader("Beratungsfolge", Icons.Default.AccountTree) }
                        items(p.consultations) { step ->
                            val done = step.status == "Erledigt"
                            StedeCard {
                                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    IconChip(if (done) Icons.Default.Check else Icons.Default.Schedule, if (done) C.green else C.heather)
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(step.committee, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                            Pill(step.status.ifEmpty { "offen" }, if (done) C.green else C.heather)
                                            step.result?.let { Pill(it, resultColor(it)) }
                                        }
                                        Text(listOf(step.role, step.date).filter { !it.isNullOrEmpty() }.joinToString(" · "), color = C.secondary, fontSize = 13.sp)
                                    }
                                }
                            }
                        }
                    }
                    p.sections.forEach { section ->
                        item { SectionHeader(section.title, Icons.Default.Notes) }
                        item {
                            StedeCard {
                                SelectionContainer {
                                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { section.paragraphs.forEach { Text(it, color = C.secondary, fontSize = 15.sp) } }
                                }
                            }
                        }
                    }
                    item { SourceFooter("Ratsinformationssystem · ${Council.host}") }
                }
            }
        }
    }
}

/** Öffnet PDFs aus dem Ratsinfo: die Temp-Adresse wird erst beim Antippen geholt. */
private class DocumentOpener(val open: (CouncilDocument, Int?) -> Unit, val opening: String?)

@Composable
private fun rememberDocumentOpener(): DocumentOpener {
    val openUrl = rememberOpenUrl()
    val scope = rememberCoroutineScope()
    var opening by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    error?.let { message ->
        AlertDialog(onDismissRequest = { error = null }, confirmButton = { TextButton({ error = null }) { Text("OK") } },
            title = { Text("Dokument nicht verfügbar") }, text = { Text(message) })
    }
    return DocumentOpener({ document, paperId ->
        scope.launch {
            opening = document.title
            runCatching { Council.documentUrl(document, paperId) }.onSuccess(openUrl).onFailure { error = "„${document.title}“ ist gerade nicht abrufbar." }
            opening = null
        }
    }, opening)
}

/** PDFs und weitere Aktionen als Kapselzeile wie in den Ortskarten. */
@Composable
private fun ActionChips(documents: List<CouncilDocument>, paperId: Int?, opener: DocumentOpener, extra: @Composable () -> Unit = {}) {
    Row(Modifier.padding(top = 10.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        documents.forEach { d ->
            // Anlagen heißen wie die Datei („Präsentation (2169 KB)“) — Größe hinten weg.
            val title = d.title.replace(Regex("\\s*\\(\\d+ KB\\)$"), "").replace(Regex("\\.pdf$", RegexOption.IGNORE_CASE), "")
            ActionChip(if (opener.opening == d.title) "Lade …" else title, if (d.dolfdnr == null) Icons.Default.AttachFile else Icons.Default.Description) {
                if (opener.opening == null) opener.open(d, paperId)
            }
        }
        extra()
    }
}
