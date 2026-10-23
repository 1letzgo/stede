package de.letzgo.stede.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*
import de.letzgo.stede.Screen

/** Start wie HomeView: Gruß mit Wetter, Unterwegs (Bahn, Bus), Zuhause (Abfuhr), Stadt. */
@Composable
fun StartScreen(open: (Screen) -> Unit) {
    val today = Town.today()
    var weather by remember { mutableStateOf(Weather.cached(today)) }
    val station = remember { Trains.station() }
    var trains by remember { mutableStateOf(Trains.cached(station)) }
    val stop = busStop(Store.string("bus.stop", ""))
    var buses by remember { mutableStateOf(Buses.cached(stop, today)) }
    val selection = remember { Waste.selection() }
    var waste by remember { mutableStateOf(selection?.let { Waste.cachedUpcoming(it) }) }
    var tides by remember { mutableStateOf(Tides.cachedEvents()) }
    var ferry by remember { mutableStateOf<List<FerryTrip>?>(null) }
    LaunchedEffect(Unit) { runCatching { Weather.load(today) }.onSuccess { weather = it } }
    // Nur Bausteine laden, die die Gemeinde hat.
    LaunchedEffect(station?.id) { if (Features.has(Feature.Train)) station?.let { s -> runCatching { Trains.load(s) }.onSuccess { trains = it } } }
    LaunchedEffect(stop.id) { if (Features.has(Feature.Bus)) runCatching { Buses.load(stop, today) }.onSuccess { buses = it } }
    LaunchedEffect(selection) { if (Features.has(Feature.Waste)) selection?.let { sel -> runCatching { Waste.upcoming(sel) }.onSuccess { waste = it } } }
    LaunchedEffect(Unit) { if (Features.has(Feature.Tides)) runCatching { Tides.events() }.onSuccess { tides = it } }
    LaunchedEffect(Unit) { if (Features.has(Feature.Ferry)) ferry = runCatching { Ferry.trips(today) }.getOrDefault(emptyList()) }
    var sessions by remember { mutableStateOf(Council.cachedSessions()) }
    var papers by remember { mutableStateOf(Council.cachedPapers()) }
    LaunchedEffect(Unit) {
        if (!Council.isAvailable) return@LaunchedEffect
        if (sessions == null || !Council.isFresh("sessions.json")) runCatching { Council.upcomingSessions() }.onSuccess { sessions = it }
        if (papers == null || !Council.isFresh("papers.json")) runCatching { Council.papers().items.also(Council::savePapers) }.onSuccess { papers = it }
    }
    val openUrl = rememberOpenUrl()

    val now = Town.now()
    val hour = now.hour
    val (greeting, tint) = when (hour) { in 5..10 -> "Guten Morgen" to C.amber; in 11..17 -> "Schönen Tag" to C.amber; in 18..21 -> "Schönen Abend" to C.red; else -> "Gute Nacht" to C.teal }
    val current = weather?.current()
    val order = remember { HomeLayout.order() }
    val hidden = remember { HomeLayout.hidden() }

    Scaffold(topBar = { StedeTopBar(Brand.current.displayName) }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                Tile(tint, Modifier.height(CompactTileHeight), onClick = { open(Screen.Weather) }, icon = weatherIcon(current?.icon, current?.condition)) {
                    Row(Modifier.fillMaxSize()) {
                        Column(Modifier.weight(1f).padding(end = 8.dp)) {
                            Text("Moin!", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = tint)
                            Text("$greeting in ${Tenants.config.municipality}", color = C.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(temp(current?.temperature), fontSize = 36.sp, fontWeight = FontWeight.Bold, color = C.text)
                            Text(listOfNotNull(current?.label, weather?.max?.let { "Max ${temp(it)}" }).joinToString(" · "), color = C.secondary, fontSize = 13.sp, maxLines = 1)
                        }
                    }
                }
            }
            for (section in order) {
                val tiles = HomeLayout.tiles(section).filter { it !in hidden }
                if (tiles.isEmpty()) continue
                item(key = section.key) { SectionHeader(section.title, section.icon) }
                when (section) {
                    HomeSection.Sea -> item(key = "sea-tiles") {
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                            for (t in tiles) {
                                if (t == HomeTileId.Tides) {
                                    val level = Tides.height(now, tides)
                                    val next = tides.firstOrNull { it.time.isAfter(now) }
                                    HomeTile("Gezeiten", Icons.Default.Waves, C.teal, Modifier.weight(1f), level?.let { Tides.meters(it) } ?: "–",
                                        next?.let { "${it.label} um ${it.time.format(Town.hm)}" } ?: "Keine Vorhersage") { open(Screen.Tides) }
                                }
                                if (t == HomeTileId.Ferry) {
                                    val config = Tenants.config.ferry
                                    fun next(toIsland: Boolean) = ferry?.filter { it.toIsland == toIsland && !it.cancelled && it.departure.isAfter(now) }?.minByOrNull { it.departure }
                                    val out = next(true); val back = next(false)
                                    fun label(trip: FerryTrip?, harbor: String?) = trip?.let { "${it.departure.format(Town.hm)} ab $harbor" } ?: "keine Abfahrt mehr ab $harbor"
                                    HomeTile("Fähre", Icons.Default.DirectionsBoat, C.red, Modifier.weight(1f),
                                        when { ferry == null -> "–"; out == null && back == null -> "Feierabend"; else -> label(out, config?.mainlandName) },
                                        when { ferry == null -> null; out == null && back == null -> "Heute keine Abfahrt mehr"; else -> label(back, config?.islandName) }) { open(Screen.Ferry) }
                                }
                            }
                        }
                    }
                    HomeSection.Transit -> item(key = "transit-tiles") {
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                            fun next(d: TrainDirection) = trains.filter { it.direction == d && !it.cancelled && it.departure.isAfter(now) }.minByOrNull { it.departure }
                            fun label(t: Train?, d: TrainDirection) = t?.let { "${it.scheduled.format(Town.hm)}${if (it.delay > 0) " +${it.delay}" else ""} · ${d.short(station)}" } ?: "kein Zug mehr · ${d.short(station)}"
                            for (t in tiles) {
                                if (t == HomeTileId.Train) {
                                    val o = next(TrainDirection.Oldenburg); val l = next(TrainDirection.Leer)
                                    HomeTile("Bahn", Icons.Default.Train, C.red, Modifier.weight(1f), if (trains.isEmpty()) "–" else if (o == null && l == null) "Feierabend" else label(o, TrainDirection.Oldenburg),
                                        if (trains.isEmpty()) null else if (o == null && l == null) "Heute keine Abfahrt mehr" else label(l, TrainDirection.Leer)) { open(Screen.Train) }
                                }
                                if (t == HomeTileId.Bus) {
                                    val b = buses?.filter { !it.cancelled && it.departure.isAfter(now) }?.minByOrNull { it.departure }
                                    HomeTile("Bus", Icons.Default.DirectionsBus, C.teal, Modifier.weight(1f),
                                        b?.let { "${it.scheduled.format(Town.hm)}${if ((it.delay ?: 0) > 0) " +${it.delay}" else ""} · ${it.line}" } ?: if (buses == null) "–" else "Feierabend",
                                        b?.let { "${it.destination} ab ${stop.short}" } ?: "Heute kein Bus mehr ab ${stop.short}") { open(Screen.Bus) }
                                }
                            }
                        }
                    }
                    HomeSection.Home -> item(key = "home-tiles") {
                        val next = waste?.firstOrNull()
                        val street = Waste.street(Store.int("waste.street"))
                        if (selection == null) HomeTile("Abfuhr", Icons.Default.Delete, C.green, Modifier.fillMaxWidth(), "Straße wählen", if (street == null) "Abfuhrkalender für deine Straße" else "Abschnitt von ${street.name} wählen", compact = true) { open(Screen.Waste) }
                        else HomeTile("Abfuhr", next?.let { wasteIcon(it.kind) } ?: Icons.Default.Delete, next?.let { wasteColor(it.kind) } ?: C.green, Modifier.fillMaxWidth(),
                            next?.let { n -> "${n.day.format(Town.dayShort)} · ${waste.orEmpty().filter { it.date == n.date }.joinToString(", ") { it.label }}" } ?: "–", street?.name, compact = true) { open(Screen.Waste) }
                    }
                    HomeSection.Politics -> item(key = "politics-tiles") {
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                            for (t in tiles) {
                                if (t == HomeTileId.Sessions) {
                                    val next = sessions?.firstOrNull { !it.isOver }
                                    HomeTile("Sitzungen", Icons.Default.Groups, C.teal, Modifier.weight(1f),
                                        next?.let { s -> s.startTime.format(Town.dayShort) + if (s.hasTime) " · ${s.startTime.format(Town.hm)}" else "" } ?: if (sessions == null) "–" else "Keine Termine",
                                        next?.committee ?: "Rat und Ausschüsse") { open(Screen.CouncilSessions) }
                                }
                                if (t == HomeTileId.Papers) {
                                    val latest = papers?.firstOrNull()
                                    HomeTile("Vorlagen", Icons.Default.Description, C.amber, Modifier.weight(1f),
                                        latest?.let { "${it.number} · ${it.date.take(6)}" } ?: if (papers == null) "–" else "Ratsinfo",
                                        latest?.subject ?: "Beschlüsse und Anträge") { open(Screen.CouncilPapers) }
                                }
                            }
                        }
                    }
                    HomeSection.City -> {
                        // Die ersten beiden Kacheln groß, die übrigen klein darunter.
                        val large = tiles.take(2).mapNotNull { it.category }
                        val small = tiles.drop(2).mapNotNull { it.category }
                        if (large.isNotEmpty()) item(key = "city-large") {
                            Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                                large.forEach { c -> CategoryTile(c, Modifier.weight(1f), TileHeight) { open(Screen.Category(c)) } }
                            }
                        }
                        // Kleine Kacheln in Viererreihen, damit auch fünf und mehr lesbar bleiben.
                        small.chunked(4).forEachIndexed { i, row ->
                            item(key = "city-small-$i") {
                                Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                                    row.forEach { c -> CategoryTile(c, Modifier.weight(1f), CompactTileHeight, small = true) { open(Screen.Category(c)) } }
                                    if (small.size > 4) repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                                }
                            }
                        }
                    }
                }
            }
            // Angebote, die auf fremden Seiten gebucht werden (Strandkörbe …).
            Tenants.config.external?.takeIf { it.isNotEmpty() }?.let { links ->
                item(key = "external-header") { SectionHeader("Externe Anbieter", Icons.Default.OpenInNew) }
                links.chunked(4).forEachIndexed { i, row ->
                    item(key = "external-$i") {
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                            row.forEach { link ->
                                Tile(C.red, Modifier.weight(1f).height(CompactTileHeight), externalIcon(link.symbol), onClick = { openUrl(link.url) }) {
                                    Text(link.title, color = C.red, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, maxLines = 2, lineHeight = 14.sp,
                                        style = androidx.compose.ui.text.TextStyle(hyphens = androidx.compose.ui.text.style.Hyphens.Auto, localeList = androidx.compose.ui.text.intl.LocaleList("de-DE")))
                                }
                            }
                            repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
            if (HomeTileId.available.all { it in hidden }) item { InfoCard("Alle Kacheln sind ausgeblendet. Unter Einstellungen → Startseite kannst du sie wieder einblenden.") }
        }
    }
}

/** SF-Symbol-Namen aus `tenants.config.external` auf Material-Symbole. */
private fun externalIcon(symbol: String): ImageVector = when {
    symbol.startsWith("beach") -> Icons.Default.BeachAccess
    symbol.startsWith("ferry") -> Icons.Default.DirectionsBoat
    symbol.startsWith("bicycle") -> Icons.Default.DirectionsBike
    symbol.startsWith("ticket") -> Icons.Default.ConfirmationNumber
    else -> Icons.Default.OpenInNew
}

/** Die beiden Kachelhöhen der Startseite — gleiche Werte wie `HomeTileMetrics` in iOS (pt = dp). */
val TileHeight = 138.dp
val CompactTileHeight = 104.dp

/** Kachel mit blasser Füllung, Rand in der Bereichsfarbe und großem Symbol in der Ecke. */
@Composable
fun Tile(color: Color, modifier: Modifier = Modifier, icon: ImageVector? = null, onClick: () -> Unit, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxWidth().clip(CardShape).background(color.copy(alpha = 0.16f)).tileBorder(color).clickable { onClick() }) {
        icon?.let { Icon(it, null, tint = color.copy(alpha = 0.28f), modifier = Modifier.size(84.dp).align(Alignment.BottomEnd).offset(x = 14.dp, y = 14.dp)) }
        Box(Modifier.padding(12.dp), content = content)
    }
}

@Composable
private fun HomeTile(title: String, icon: ImageVector, color: Color, modifier: Modifier, headline: String, detail: String?, compact: Boolean = false, onClick: () -> Unit) {
    Tile(color, modifier.height(if (compact) CompactTileHeight else TileHeight), icon, onClick) {
        Column(verticalArrangement = Arrangement.spacedBy(if (compact) 2.dp else 4.dp)) {
            Text(title, color = color, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Text(headline, color = C.text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = if (compact) 1 else 2, overflow = TextOverflow.Ellipsis)
            detail?.let { Text(it, color = C.secondary, fontSize = 13.sp, maxLines = if (compact) 1 else 2, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@Composable
private fun CategoryTile(category: String, modifier: Modifier, height: Dp, small: Boolean = false, onClick: () -> Unit) {
    val color = Catalog.color(category)
    Tile(color, modifier.height(height), Catalog.icon(category), onClick) {
        // Gleiche Schrifthöhe in allen Kacheln: lange Namen werden getrennt und stehen zweizeilig, statt zu schrumpfen.
        Text(Catalog.tileTitle(category), color = color, fontWeight = FontWeight.SemiBold,
            fontSize = if (small) 12.sp else 18.sp, maxLines = 2, overflow = TextOverflow.Ellipsis, lineHeight = if (small) 14.sp else 22.sp,
            style = androidx.compose.ui.text.TextStyle(hyphens = androidx.compose.ui.text.style.Hyphens.Auto, localeList = androidx.compose.ui.text.intl.LocaleList("de-DE")))
    }
}
