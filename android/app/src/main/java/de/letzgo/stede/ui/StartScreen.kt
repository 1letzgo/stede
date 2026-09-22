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
    var trains by remember { mutableStateOf(Trains.cached()) }
    val stop = busStop(Store.string("bus.stop", busStops.first().id))
    var buses by remember { mutableStateOf(Buses.cached(stop, today)) }
    val selection = remember { Waste.selection() }
    var waste by remember { mutableStateOf(selection?.let { Waste.cachedUpcoming(it) }) }
    LaunchedEffect(Unit) { runCatching { Weather.load(today) }.onSuccess { weather = it } }
    LaunchedEffect(Unit) { runCatching { Trains.load() }.onSuccess { trains = it } }
    LaunchedEffect(stop.id) { runCatching { Buses.load(stop, today) }.onSuccess { buses = it } }
    LaunchedEffect(selection) { selection?.let { sel -> runCatching { Waste.upcoming(sel) }.onSuccess { waste = it } } }

    val now = Town.now()
    val hour = now.hour
    val (greeting, tint) = when (hour) { in 5..10 -> "Guten Morgen" to C.amber; in 11..17 -> "Schönen Tag" to C.amber; in 18..21 -> "Schönen Abend" to C.red; else -> "Gute Nacht" to C.teal }
    val current = weather?.current()

    Scaffold(topBar = { StedeTopBar("stede") }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            item {
                Tile(tint, Modifier.height(120.dp), onClick = { open(Screen.Weather) }, icon = weatherIcon(current?.icon, current?.condition)) {
                    Row(Modifier.fillMaxSize()) {
                        Column(Modifier.weight(1f).padding(end = 8.dp)) {
                            Text("Moin!", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = tint)
                            Text("$greeting in Westerstede", color = C.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(temp(current?.temperature), fontSize = 36.sp, fontWeight = FontWeight.Bold, color = C.text)
                            Text(listOfNotNull(current?.label, weather?.max?.let { "Max ${temp(it)}" }).joinToString(" · "), color = C.secondary, fontSize = 13.sp, maxLines = 1)
                        }
                    }
                }
            }
            item { SectionHeader("Unterwegs", Icons.Default.Train) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                    fun next(d: TrainDirection) = trains.filter { it.direction == d && !it.cancelled && it.departure.isAfter(now) }.minByOrNull { it.departure }
                    fun label(t: Train?, d: TrainDirection) = t?.let { "${it.scheduled.format(Town.hm)}${if (it.delay > 0) " +${it.delay}" else ""} · ${d.short}" } ?: "kein Zug mehr · ${d.short}"
                    val o = next(TrainDirection.Oldenburg); val l = next(TrainDirection.Leer)
                    HomeTile("Bahn", Icons.Default.Train, C.red, Modifier.weight(1f), if (trains.isEmpty()) "–" else if (o == null && l == null) "Feierabend" else label(o, TrainDirection.Oldenburg),
                        if (trains.isEmpty()) null else if (o == null && l == null) "Heute keine Abfahrt mehr" else label(l, TrainDirection.Leer)) { open(Screen.Train) }
                    val b = buses?.filter { !it.cancelled && it.departure.isAfter(now) }?.minByOrNull { it.departure }
                    HomeTile("Bus", Icons.Default.DirectionsBus, C.teal, Modifier.weight(1f),
                        b?.let { "${it.scheduled.format(Town.hm)}${if ((it.delay ?: 0) > 0) " +${it.delay}" else ""} · ${it.line}" } ?: if (buses == null) "–" else "Feierabend",
                        b?.let { "${it.destination} ab ${stop.short}" } ?: "Heute kein Bus mehr ab ${stop.short}") { open(Screen.Bus) }
                }
            }
            item { SectionHeader("Zuhause", Icons.Default.Home) }
            item {
                val next = waste?.firstOrNull()
                val street = Waste.street(Store.int("waste.street"))
                if (selection == null) HomeTile("Abfuhr", Icons.Default.Delete, C.green, Modifier.fillMaxWidth(), "Straße wählen", if (street == null) "Abfuhrkalender für deine Straße" else "Abschnitt von ${street.name} wählen", height = 112.dp) { open(Screen.Waste) }
                else HomeTile("Abfuhr", next?.let { wasteIcon(it.kind) } ?: Icons.Default.Delete, next?.let { wasteColor(it.kind) } ?: C.green, Modifier.fillMaxWidth(),
                    next?.let { "${it.day.format(Town.dayShort)} · ${it.label}" } ?: "–", street?.name, height = 112.dp) { open(Screen.Waste) }
            }
            item { SectionHeader("Stadt", Icons.Default.Map) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                    listOf(Catalog.DISCOVER, Catalog.GASTRO).forEach { c -> CategoryTile(c, Modifier.weight(1f), 150.dp) { open(Screen.Category(c)) } }
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                    listOf(Catalog.SHOPPING, Catalog.PLAYGROUNDS, Catalog.TRIPS, Catalog.HEALTH).forEach { c -> CategoryTile(c, Modifier.weight(1f), 86.dp, small = true) { open(Screen.Category(c)) } }
                }
            }
        }
    }
}

/** Kachel mit blasser Füllung, Rand in der Bereichsfarbe und großem Symbol in der Ecke. */
@Composable
fun Tile(color: Color, modifier: Modifier = Modifier, icon: ImageVector? = null, onClick: () -> Unit, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxWidth().clip(CardShape).background(color.copy(alpha = 0.16f)).tileBorder(color).clickable { onClick() }) {
        icon?.let { Icon(it, null, tint = color.copy(alpha = 0.28f), modifier = Modifier.size(84.dp).align(Alignment.BottomEnd).offset(x = 14.dp, y = 14.dp)) }
        Box(Modifier.padding(12.dp), content = content)
    }
}

@Composable
private fun HomeTile(title: String, icon: ImageVector, color: Color, modifier: Modifier, headline: String, detail: String?, height: Dp = 130.dp, onClick: () -> Unit) {
    Tile(color, modifier.height(height), icon, onClick) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, color = color, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
            Text(headline, color = C.text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            detail?.let { Text(it, color = C.secondary, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@Composable
private fun CategoryTile(category: String, modifier: Modifier, height: Dp, small: Boolean = false, onClick: () -> Unit) {
    val color = Catalog.color(category)
    Tile(color, modifier.height(height), Catalog.icon(category), onClick) {
        Text(category, color = color, fontWeight = FontWeight.SemiBold, fontSize = if (small) 12.sp else 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}
