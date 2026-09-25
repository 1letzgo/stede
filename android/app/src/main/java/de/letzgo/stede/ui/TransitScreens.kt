package de.letzgo.stede.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*
import kotlinx.coroutines.launch
import java.time.LocalDate

// MARK: Bahn

@Composable
fun TrainScreen(onBack: () -> Unit) {
    var direction by remember { mutableStateOf(runCatching { TrainDirection.valueOf(Store.string("train.direction", "Oldenburg").replaceFirstChar { it.uppercase() }) }.getOrDefault(TrainDirection.Oldenburg)) }
    var trains by remember { mutableStateOf(Trains.cached()) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()
    suspend fun load(force: Boolean) { loading = true; runCatching { Trains.load(force) }.onSuccess { trains = it; error = null }.onFailure { if (trains.isEmpty()) error = it.message }; loading = false }
    LaunchedEffect(Unit) { load(false) }
    val list = trains.filter { it.direction == direction }
    val now = Town.now()
    val nextId = list.firstOrNull { it.departure.isAfter(now) && !it.cancelled }?.id
    Scaffold(topBar = { StedeTopBar("Bahn", onBack) { IconButton(onClick = { scope.launch { load(true) } }) { Icon(Icons.Default.Refresh, "Aktualisieren") } } }, containerColor = C.sand) { pad ->
        Column(Modifier.padding(pad)) {
            Spacer(Modifier.height(16.dp))
            Switcher(TrainDirection.entries, direction, { it.title }) { direction = it; Store.setString("train.direction", it.name.lowercase()) }
            LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                if (list.isEmpty()) item { if (loading) Loading() else InfoCard(error ?: "Gerade stehen keine Abfahrten auf der Tafel.") }
                items(list, key = { it.id }) { t -> TrainCard(t, t.id == nextId, t.departure.isBefore(now)) }
                item { SourceFooter("Bahnhof Westerstede-Ocholt · dbf.finalrewind.org (DB IRIS), nächste rund zwei Stunden") }
            }
        }
    }
}

@Composable
private fun TrainCard(t: Train, isNext: Boolean, isPast: Boolean) {
    StedeCard(highlighted = isNext && !t.cancelled, modifier = Modifier.then(if (isPast) Modifier.background(Color.Transparent) else Modifier)) {
        Column(Modifier.fillMaxWidth().then(if (isPast) Modifier.padding(0.dp) else Modifier)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(t.scheduled.format(Town.hm), fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = C.text.copy(alpha = if (isPast) 0.5f else 1f), textDecoration = if (t.cancelled) TextDecoration.LineThrough else null)
                if (t.cancelled) Text("fällt aus", color = C.red, fontWeight = FontWeight.SemiBold, fontSize = 12.sp) else if (t.delay > 0) Text("+${t.delay}", color = C.red, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                if (isNext && !t.cancelled) Pill("Nächster", C.teal)
                Text(t.line, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.background(C.deep, RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp))
                t.platform?.let { Text("Gl. $it", fontSize = 12.sp, color = if (t.platformChanged) C.red else C.secondary) }
            }
            val stops = t.via.take(3)
            Text(if (stops.isEmpty()) "nach ${t.destination}" else "nach ${t.destination} · über ${stops.joinToString(", ")}", fontSize = 15.sp, color = C.secondary, modifier = Modifier.padding(top = 6.dp))
            if (!t.cancelled) t.notes.firstOrNull()?.let { Text(it, fontSize = 12.sp, color = C.red, modifier = Modifier.padding(top = 4.dp)) }
        }
    }
}

// MARK: Bus

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BusScreen(onBack: () -> Unit) {
    val stopId = remember { Store.string("bus.stop", busStops.first().id) }
    var day by remember { mutableStateOf(Town.today()) }
    var buses by remember { mutableStateOf<List<Bus>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val stop = busStop(stopId)
    LaunchedEffect(stopId, day) {
        buses = Buses.cached(stop, day)
        runCatching { Buses.load(stop, day) }.onSuccess { buses = it; error = null }.onFailure { if (buses == null) error = it.message }
    }
    val now = Town.now()
    val visible = (buses ?: emptyList()).filter { day != Town.today() || !it.departure.isBefore(now) }
    val nextId = visible.firstOrNull { !it.cancelled }?.id.takeIf { day == Town.today() }
    Scaffold(topBar = { StedeTopBar("Bus", onBack, subtitle = "ab ${stop.short}") }, containerColor = C.sand) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            Column {
                LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                    when {
                        buses == null && error == null -> item { Loading() }
                        visible.isEmpty() -> item { InfoCard(error ?: if (day == Town.today()) "Heute fährt hier kein Bus mehr." else "Für diesen Tag stehen hier keine Abfahrten im Fahrplan.") }
                    }
                    items(visible, key = { it.id }) { b -> BusCard(b, b.id == nextId) }
                    item { SourceFooter("${stop.name} · VBN-Fahrplaner, fahrplaner.vbn.de") }
                }
            }
            DayBar(day, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp)) { day = it }
        }
    }
}

/** Haltestellenliste als Sheet — aus Bus und Einstellungen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BusStopSheet(selected: String, onPick: (String) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader("Haltestelle", trailing = "Fertig" to onDismiss)
        LazyColumn(contentPadding = PaddingValues(16.dp)) {
            items(busStops) { s ->
                Row(Modifier.fillMaxWidth().clickable { onPick(s.id); onDismiss() }.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(s.short, Modifier.weight(1f), color = C.text, fontSize = 16.sp)
                    if (s.id == selected) Icon(Icons.Default.Check, null, tint = C.ink)
                }
                HorizontalDivider(color = C.tertiary.copy(alpha = 0.2f))
            }
        }
    }
}

@Composable
private fun BusCard(b: Bus, isNext: Boolean) {
    StedeCard(highlighted = isNext && !b.cancelled) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(b.scheduled.format(Town.hm), fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = C.text, textDecoration = if (b.cancelled) TextDecoration.LineThrough else null)
            if (b.cancelled) Text("fällt aus", color = C.red, fontWeight = FontWeight.SemiBold, fontSize = 12.sp) else if ((b.delay ?: 0) > 0) Text("+${b.delay}", color = C.red, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            if (isNext && !b.cancelled) Pill("Nächster", C.teal)
            Text(b.line, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.background(C.deep, RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp))
        }
        Row(Modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("nach ${b.destination}", Modifier.weight(1f), fontSize = 15.sp, color = C.secondary)
            b.platform?.let { Text("Steig $it", fontSize = 12.sp, color = C.secondary) }
        }
    }
}

// MARK: Abfuhr

fun wasteIcon(kind: WasteKind) = when (kind) {
    WasteKind.Rest -> Icons.Default.Delete; WasteKind.Papier -> Icons.Default.Newspaper; WasteKind.Gelb -> Icons.Default.ShoppingBag
    WasteKind.Bio -> Icons.Default.Eco; WasteKind.Ast -> Icons.Default.Forest; WasteKind.Problem -> Icons.Default.Warning; WasteKind.Sonst -> Icons.Default.DeleteOutline
}
@Composable
fun wasteColor(kind: WasteKind) = when (kind) {
    WasteKind.Rest -> C.ink; WasteKind.Papier -> C.teal; WasteKind.Gelb -> C.amber; WasteKind.Bio -> C.green
    WasteKind.Ast -> C.mudflat; WasteKind.Problem -> C.red; WasteKind.Sonst -> C.heather
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WasteScreen(onBack: () -> Unit, openSettings: () -> Unit) {
    val streetId = remember { Store.int("waste.street") }
    var items by remember { mutableStateOf<List<WasteCollection>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val street = Waste.street(streetId)
    val selection = remember { Waste.selection() }
    LaunchedEffect(selection) {
        items = null; error = null
        val sel = selection ?: return@LaunchedEffect
        items = Waste.cachedUpcoming(sel)
        runCatching { Waste.upcoming(sel) }.onSuccess { items = it }.onFailure { if (items == null) error = it.message }
    }
    Scaffold(topBar = { StedeTopBar("Abfuhr", onBack, subtitle = street?.name) }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            when {
                selection == null -> item {
                    StedeCard {
                        Text(if (street == null) "Wähle deine Straße in den Einstellungen, dann erscheinen hier die Abfuhrtermine." else "Wähle in den Einstellungen den Abschnitt deiner Straße.", color = C.secondary)
                        ColorChip("Zu den Einstellungen", C.ink, Modifier.padding(top = 10.dp), icon = Icons.Default.Settings, prominent = true, onClick = openSettings)
                    }
                }
                items == null && error == null -> item { Loading() }
                error != null -> item { InfoCard(error!!) }
                else -> {
                    val list = items!!
                    list.groupBy { it.day.withDayOfMonth(1) }.forEach { (month, entries) ->
                        item(key = month.toString()) { SectionHeader(month.format(Town.fmt("MMMM yyyy")), Icons.Default.CalendarMonth) }
                        items(entries, key = { it.date + it.label }) { c -> WasteCard(c, c == list.first()) }
                    }
                    item { SourceFooter("${Waste.source} · appfuhr.de · Angaben ohne Gewähr") }
                }
            }
        }
    }
}

/** Suchbare Straßenliste — aus Abfuhr und Einstellungen. Setzt bei neuer Straße die Abschnitte zurück. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StreetSheet(selected: Int, onPick: (Int) -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        var query by remember { mutableStateOf("") }
        SheetHeader("Straße", trailing = "Fertig" to onDismiss)
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp), placeholder = { Text("Straße in Westerstede") }, singleLine = true, leadingIcon = { Icon(Icons.Default.Search, null) })
        LazyColumn(contentPadding = PaddingValues(16.dp)) {
            items(Waste.streets.filter { query.isBlank() || it.name.contains(query.trim(), ignoreCase = true) }, key = { it.id }) { s ->
                Row(Modifier.fillMaxWidth().clickable {
                    if (s.id != selected) { Store.setInt("waste.street", s.id); Store.setInt("waste.section", 0); Store.setInt("waste.branchSection", 0) }
                    onPick(s.id); onDismiss()
                }.padding(vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(s.name, Modifier.weight(1f), color = C.text, fontSize = 16.sp)
                    if (s.id == selected) Icon(Icons.Default.Check, null, tint = C.ink)
                }
                HorizontalDivider(color = C.tertiary.copy(alpha = 0.2f))
            }
        }
    }
}

@Composable
fun SectionPicker(title: String, sections: List<WasteSection>, selected: Int, onSelect: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, fontSize = 13.sp, color = C.secondary)
        Row(Modifier.horizontalScrollCompat(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { sections.forEach { s -> SelectionChip(s.label, s.id == selected) { onSelect(s.id) } } }
    }
}

@Composable
private fun Modifier.horizontalScrollCompat() = this.then(Modifier.horizontalScroll(androidx.compose.foundation.rememberScrollState()))

@Composable
private fun WasteCard(c: WasteCollection, isNext: Boolean) {
    val color = wasteColor(c.kind)
    StedeCard(highlighted = isNext) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconChip(wasteIcon(c.kind), color)
            Column(Modifier.weight(1f)) {
                Text(c.label, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                Text(c.day.format(Town.dayShort), fontSize = 14.sp, color = C.secondary)
            }
            if (isNext) {
                val days = java.time.temporal.ChronoUnit.DAYS.between(Town.today(), c.day)
                Pill(when (days) { 0L -> "Heute"; 1L -> "Morgen"; else -> "in $days Tagen" }, color)
            }
        }
    }
}
