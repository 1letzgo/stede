package de.letzgo.stede.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*
import java.time.Duration

// MARK: Fähre — wie FerryView in iOS

private enum class Harbor { Mainland, Island }

@Composable
fun FerryScreen(onBack: () -> Unit) {
    val ferry = Tenants.config.ferry
    var day by remember { mutableStateOf(Town.today()) }
    var harbor by remember { mutableStateOf(Harbor.Mainland) }
    var trips by remember { mutableStateOf<List<FerryTrip>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val openUrl = rememberOpenUrl()
    LaunchedEffect(day) {
        trips = null; error = null
        runCatching { Ferry.trips(day) }.onSuccess { trips = it }.onFailure { error = "Die Fährzeiten konnten nicht geladen werden." }
    }
    val list = trips?.filter { it.toIsland == (harbor == Harbor.Mainland) }.orEmpty()
    val now = Town.now(); val isToday = day == Town.today()
    val nextId = if (isToday) list.firstOrNull { it.departure.isAfter(now) && !it.cancelled }?.number else null
    fun name(h: Harbor) = if (h == Harbor.Mainland) ferry?.mainlandName ?: "Festland" else ferry?.islandName ?: "Insel"
    Scaffold(topBar = { StedeTopBar("Fähre", onBack) }, containerColor = C.sand) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            Column {
                Spacer(Modifier.height(16.dp))
                Switcher(Harbor.entries, harbor, { name(it) }) { harbor = it }
                LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                    when {
                        trips == null && error == null -> item { Loading() }
                        error != null -> item { InfoCard(error!!) }
                        trips!!.isEmpty() -> item { InfoCard("Für diesen Tag sind keine Fährzeiten hinterlegt.") }
                        list.isEmpty() -> item { InfoCard("Keine Fahrten ab ${name(harbor)}") }
                    }
                    items(list, key = { it.number }) { t ->
                        FerryCard(t, t.number == nextId, isToday && t.departure.isBefore(now)) { ferry?.bookingUrl?.let(openUrl) }
                    }
                    ferry?.source?.let { item { SourceFooter(it) } }
                }
            }
            DayBar(day, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp)) { day = it }
        }
    }
}

@Composable
private fun FerryCard(t: FerryTrip, isNext: Boolean, isPast: Boolean, book: () -> Unit) {
    val alpha = if (isPast) 0.55f else 1f
    StedeCard(highlighted = isNext && !t.cancelled, onClick = if (t.cancelled) null else book) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("${t.departure.format(Town.hm)} → ${t.arrival.format(Town.hm)}", fontSize = 20.sp, fontWeight = FontWeight.SemiBold,
                color = C.text.copy(alpha = alpha), textDecoration = if (t.cancelled) TextDecoration.LineThrough else null)
            if (t.cancelled) Text("fällt aus", color = C.red, fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
            if (t.excursion) Text("Ausflug", color = C.secondary, fontSize = 11.sp)
            Spacer(Modifier.weight(1f))
            if (isNext && !t.cancelled) Pill("Nächste", C.teal)
            Text(t.vessel, fontSize = 12.sp, color = C.secondary, maxLines = 1)
        }
        if (!t.cancelled) t.occupancy?.let { p ->
            Text("Auslastung $p %", fontSize = 11.sp, color = C.secondary, modifier = Modifier.padding(top = 6.dp))
            val color = when { p < 50 -> C.green; p < 80 -> C.amber; else -> C.red }
            Box(Modifier.padding(top = 4.dp).fillMaxWidth().height(5.dp).background(color.copy(alpha = 0.18f))) {
                Box(Modifier.fillMaxWidth(p.coerceIn(0, 100) / 100f).fillMaxHeight().background(color))
            }
        }
    }
}

// MARK: Gezeiten — wie TideView in iOS

@Composable
fun TideScreen(onBack: () -> Unit) {
    var day by remember { mutableStateOf(Town.today()) }
    var events by remember { mutableStateOf(Tides.cachedEvents()) }
    var measured by remember { mutableStateOf<List<WaterLevel>>(emptyList()) }
    var loading by remember { mutableStateOf(events.isEmpty()) }
    LaunchedEffect(Unit) { runCatching { Tides.events() }.onSuccess { events = it }; loading = false }
    LaunchedEffect(day) {
        measured = emptyList()
        if (!day.isAfter(Town.today()) && day.isAfter(Town.today().minusDays(31))) runCatching { Tides.measured(day) }.onSuccess { measured = it }
    }
    val isToday = day == Town.today()
    val dayEvents = events.filter { it.time.toLocalDate() == day }
    val curve = remember(events, day) { Tides.curve(events, day) }
    val now = Town.now()
    val current = if (isToday) measured.lastOrNull()?.takeIf { Duration.between(it.time, now).toMinutes() < 90 }?.value ?: Tides.height(now, events) else null
    val next = if (isToday) events.firstOrNull { it.time.isAfter(now) } else null
    Scaffold(topBar = { StedeTopBar("Gezeiten", onBack) }, containerColor = C.sand) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                if (events.isEmpty()) { item { if (loading) Loading() else InfoCard("Für diesen Tag liegen keine Gezeiten vor.") }; return@LazyColumn }
                item { StedeCard(highlighted = true) { TideChart(curve, measured, dayEvents, if (isToday) now else null) } }
                item { SectionHeader(if (isToday) "Wasserstand" else "Tidenhub", Icons.Default.ShowChart) }
                item {
                    StedeCard {
                        if (current != null) {
                            Text(Tides.meters(current), fontSize = 34.sp, fontWeight = FontWeight.Bold, color = C.text)
                            next?.let { Text("${if (it.high) "steigend" else "fallend"} · ${it.label} um ${it.time.format(Town.hm)}", color = C.secondary) }
                        } else {
                            val hi = dayEvents.filter { it.high }.maxOfOrNull { it.height }; val lo = dayEvents.filter { !it.high }.minOfOrNull { it.height }
                            Text(if (hi != null && lo != null) Tides.meters(hi - lo) else "–", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = C.text)
                            Text("Unterschied zwischen Hoch- und Niedrigwasser", color = C.secondary)
                        }
                        Text("Höhen über Seekartennull", fontSize = 12.sp, color = C.tertiary, modifier = Modifier.padding(top = 4.dp))
                    }
                }
                item { SectionHeader("Hoch- & Niedrigwasser", Icons.Default.Waves) }
                dayEvents.chunked(2).forEachIndexed { i, row ->
                    item(key = "tide-$i") {
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                            row.forEach { e ->
                                StedeCard(Modifier.weight(1f)) {
                                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Icon(if (e.high) Icons.Default.VerticalAlignTop else Icons.Default.VerticalAlignBottom, null, tint = if (e.high) C.teal else C.mudflat, modifier = Modifier.size(16.dp))
                                        Text(e.label, fontSize = 13.sp, color = if (e.high) C.teal else C.mudflat, fontWeight = FontWeight.SemiBold)
                                    }
                                    Text("${e.time.format(Town.hm)} · ${Tides.meters(e.height)}", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.text, modifier = Modifier.padding(top = 4.dp))
                                    e.phaseLabel?.let { Text(it, fontSize = 12.sp, color = C.secondary) }
                                }
                            }
                            if (row.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                }
                item { SourceFooter("BSH Gezeiten · PEGELONLINE WSV${Tenants.config.tides?.gaugeName?.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: ""}") }
            }
            DayBar(day, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp)) { day = it }
        }
    }
}

/** Vorausberechnete Kurve (Fläche), gemessener Pegel (Linie), Jetzt-Marke. */
@Composable
private fun TideChart(curve: List<WaterLevel>, measured: List<WaterLevel>, extrema: List<TideEvent>, now: java.time.ZonedDateTime?) {
    val fill = C.teal; val line = C.ink; val mark = C.red
    val values = curve.map { it.value } + measured.map { it.value }
    if (values.isEmpty()) return
    val lo = values.min() - 0.3; val hi = values.max() + 0.3
    val start = curve.firstOrNull()?.time ?: return
    Canvas(Modifier.fillMaxWidth().height(200.dp)) {
        fun x(t: java.time.ZonedDateTime) = (Duration.between(start, t).toMinutes() / 1440f) * size.width
        fun y(v: Double) = (size.height - (v - lo) / (hi - lo) * size.height).toFloat()
        val area = Path().apply {
            moveTo(0f, size.height)
            curve.forEach { lineTo(x(it.time), y(it.value)) }
            lineTo(size.width, size.height); close()
        }
        drawPath(area, fill.copy(alpha = 0.22f))
        val outline = Path(); curve.forEachIndexed { i, p -> if (i == 0) outline.moveTo(x(p.time), y(p.value)) else outline.lineTo(x(p.time), y(p.value)) }
        drawPath(outline, fill, style = Stroke(width = 2.dp.toPx()))
        if (measured.size > 1) {
            val m = Path(); measured.forEachIndexed { i, p -> if (i == 0) m.moveTo(x(p.time), y(p.value)) else m.lineTo(x(p.time), y(p.value)) }
            drawPath(m, line, style = Stroke(width = 2.5.dp.toPx()))
        }
        extrema.forEach { e -> drawCircle(if (e.high) fill else line, 4.dp.toPx(), Offset(x(e.time), y(e.height))) }
        now?.let { n -> val nx = x(n); drawLine(mark, Offset(nx, 0f), Offset(nx, size.height), strokeWidth = 1.5.dp.toPx()) }
    }
    Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        listOf("0", "6", "12", "18", "24").forEach { Text(it, fontSize = 11.sp, color = C.secondary) }
    }
    if (measured.isNotEmpty()) Text("Fläche: Vorhersage · Linie: gemessen", fontSize = 11.sp, color = C.secondary, modifier = Modifier.padding(top = 2.dp))
}
