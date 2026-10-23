package de.letzgo.stede.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*
import java.time.LocalDate
import kotlin.math.roundToInt

fun weatherIcon(icon: String?, condition: String? = null): ImageVector = when (condition) {
    "rain" -> Icons.Default.Umbrella; "snow", "sleet" -> Icons.Default.AcUnit; "thunderstorm" -> Icons.Default.FlashOn; "hail" -> Icons.Default.Grain
    else -> when (icon) {
        "clear-day" -> Icons.Default.WbSunny; "clear-night", "partly-cloudy-night" -> Icons.Default.NightsStay
        "partly-cloudy-day" -> Icons.Default.WbCloudy; "wind" -> Icons.Default.Air; "rain" -> Icons.Default.Umbrella; else -> Icons.Default.Cloud
    }
}
fun temp(v: Double?) = v?.let { "${it.roundToInt()}°" } ?: "–"

@Composable
fun WeatherScreen(onBack: () -> Unit) {
    var day by remember { mutableStateOf(Town.today()) }
    var weather by remember { mutableStateOf<WeatherDay?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var selectedHour by remember { mutableStateOf<String?>(null) }
    var air by remember { mutableStateOf<List<AirHour>>(emptyList()) }
    var marine by remember { mutableStateOf<List<MarineHour>>(emptyList()) }
    LaunchedEffect(day) { air = emptyList(); if (Features.has(Feature.Air)) air = runCatching { Air.hours(day) }.getOrDefault(emptyList()) }
    LaunchedEffect(Unit) { marine = runCatching { Marine.hours() }.getOrDefault(emptyList()) }
    LaunchedEffect(day) {
        weather = Weather.cached(day); error = null; selectedHour = null
        runCatching { Weather.load(day) }.onSuccess { weather = it }.onFailure { if (weather == null) error = it.message }
    }
    val w = weather
    val isToday = day == Town.today()
    val anchor = w?.let { if (isToday) it.current() else it.hours.firstOrNull { h -> h.time.hour == 12 } ?: it.hours.firstOrNull() }
    val selected = w?.hours?.firstOrNull { it.timestamp == selectedHour } ?: anchor
    // Wind und Seegang der gewählten Stunde (höchstens 90 Minuten daneben) — nur auf den Inseln.
    val wind = selected?.let { h -> marine.minByOrNull { kotlin.math.abs(java.time.Duration.between(it.time, h.time).toMinutes()) }
        ?.takeIf { kotlin.math.abs(java.time.Duration.between(it.time, h.time).toMinutes()) <= 90 } }
    Scaffold(topBar = { StedeTopBar("Wetter", onBack) }, containerColor = C.sand) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                if (w == null || selected == null) { item { if (error != null) InfoCard(error!!) else Loading() }; return@LazyColumn }
                item { WeatherHero(selected, if (isToday && selected.timestamp == anchor?.timestamp) "Jetzt" else selected.time.format(Town.hm), w) }
                wind?.let { m ->
                    item { SectionHeader("Wind & See", Icons.Default.Air) }
                    item { MarineCard(m, marine.filter { it.time.toLocalDate() == day }, Tenants.config.marine?.name) }
                }
                item { SectionHeader("Stündlich", Icons.Default.Schedule) }
                item { HourStrip(w.hours, selected.timestamp, if (isToday) anchor?.timestamp else null) { selectedHour = it } }
                item { SectionHeader("Tagesverlauf", Icons.Default.ShowChart) }
                item { StedeCard { DayChart(w, selected) } }
                item { SectionHeader("Details um ${selected.time.format(Town.hm)}", Icons.Default.GridView) }
                item { DetailGrid(selected, w, air) }
                item { SourceFooter("Deutscher Wetterdienst über Bright Sky${w.station?.let { " · Station $it" } ?: ""}" +
                    (Tenants.config.airStation?.takeIf { air.isNotEmpty() }?.let { " · Luft: Umweltbundesamt $it" } ?: "")) }
            }
            DayBar(day, latest = Town.today().plusDays(9), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp)) { day = it }
        }
    }
}

/** Kopf wie WeatherHero in iOS: Stunde, Temperatur, Zustand, Tageswerte. */
@Composable
private fun WeatherHero(h: WeatherHour, badge: String, w: WeatherDay) {
    StedeCard(highlighted = true) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(badge, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = C.ink,
                    modifier = Modifier.background(C.surface.copy(alpha = 0.6f), RoundedCornerShape(50)).padding(horizontal = 10.dp, vertical = 3.dp))
                Text(temp(h.temperature), fontSize = 52.sp, fontWeight = FontWeight.SemiBold, color = C.text)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(h.label, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                    Icon(weatherIcon(h.icon, h.condition), null, tint = C.teal, modifier = Modifier.size(36.dp))
                }
                Text("↑ ${temp(w.max)}   ↓ ${temp(w.min)}   ${"%.1f".format(Town.locale, w.rain)} mm", color = C.secondary, fontSize = 14.sp)
            }
        }
    }
}

/** Wind und Seegang vor der Insel, groß unter dem Kopf — wie MarineWindCard in iOS. */
@Composable
private fun MarineCard(m: MarineHour, dayHours: List<MarineHour>, place: String?) {
    val color = marineColor(m.beaufort)
    StedeCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(58.dp).background(color.copy(alpha = 0.16f), androidx.compose.foundation.shape.CircleShape), contentAlignment = Alignment.Center) {
                // Der Pfeil zeigt, wohin der Wind weht.
                if (m.windDirection != null) Icon(Icons.Default.Navigation, null, tint = color, modifier = Modifier.size(30.dp).rotate((m.windDirection + 180).toFloat()))
            }
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${m.beaufort ?: 0}", fontSize = 40.sp, fontWeight = FontWeight.SemiBold, color = C.text)
                    Text("Bft", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = C.secondary, modifier = Modifier.padding(bottom = 6.dp))
                }
                Text(listOfNotNull(m.compass?.let { "aus $it" }, m.beaufortName).joinToString(" · "), color = color, fontWeight = FontWeight.Medium, fontSize = 14.sp)
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                m.kmh?.let { Text("${it.roundToInt()} km/h", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text) }
                m.knots?.let { Text("${it.roundToInt()} kn", fontSize = 14.sp, color = C.secondary) }
                m.waveHeight?.let { Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Default.Waves, null, tint = C.teal, modifier = Modifier.size(16.dp))
                    Text("${"%.1f".format(Town.locale, it)} m", color = C.teal, fontWeight = FontWeight.Medium, fontSize = 14.sp)
                } }
            }
        }
        val steps = dayHours.filter { it.time.hour % 3 == 0 }
        if (steps.size > 1) {
            HorizontalDivider(Modifier.padding(vertical = 12.dp), color = C.tertiary.copy(alpha = 0.25f))
            Row(Modifier.fillMaxWidth()) {
                steps.forEach { s ->
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("${s.time.hour}", fontSize = 11.sp, color = C.secondary)
                        Icon(Icons.Default.Navigation, null, tint = marineColor(s.beaufort), modifier = Modifier.size(14.dp).rotate(((s.windDirection ?: 0.0) + 180).toFloat()))
                        Text("${s.beaufort ?: 0}", fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = if (s.time == m.time) marineColor(s.beaufort) else C.text)
                    }
                }
            }
        }
        Text("Wind 10 m und Wellen${place?.let { " · $it" } ?: ""} · DWD-Seegangsmodell wie marineforecast.bsh.de",
            fontSize = 11.sp, color = C.secondary, modifier = Modifier.padding(top = 10.dp))
    }
}

/** Bis 4 Bft ruhig, 5–6 kräftig, ab 7 stürmisch. */
@Composable
private fun marineColor(bft: Int?) = when (bft ?: 0) { in 0..4 -> C.teal; in 5..6 -> C.amber; else -> C.red }

/** Stundenleiste in einer Karte, alle Spalten gleich hoch, springt zur gewählten Stunde. */
@Composable
private fun HourStrip(hours: List<WeatherHour>, selected: String, current: String?, onSelect: (String) -> Unit) {
    val state = androidx.compose.foundation.lazy.rememberLazyListState()
    LaunchedEffect(hours, selected) {
        val i = hours.indexOfFirst { it.timestamp == selected }
        if (i >= 0) state.animateScrollToItem((i - 2).coerceAtLeast(0))
    }
    StedeCard(padding = 8.dp) {
        LazyRow(state = state, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            items(hours, key = { it.timestamp }) { h ->
                val chosen = h.timestamp == selected
                Column(Modifier.width(54.dp).background(if (chosen) C.teal.copy(alpha = 0.18f) else androidx.compose.ui.graphics.Color.Transparent, CardShape)
                    .clickable { onSelect(h.timestamp) }.padding(vertical = 10.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(if (h.timestamp == current) "Jetzt" else h.time.format(Town.fmt("HH")), fontSize = 13.sp,
                        fontWeight = if (h.timestamp == current) FontWeight.SemiBold else FontWeight.Normal, color = if (h.timestamp == current) C.red else C.secondary)
                    Icon(weatherIcon(h.icon, h.condition), null, tint = C.teal, modifier = Modifier.size(24.dp))
                    Text(temp(h.temperature), fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                    // Immer eine Zeile, damit alle Spalten gleich hoch sind.
                    Text((h.precipitation ?: 0.0).takeIf { it > 0 }?.let { "%.1f".format(Town.locale, it) } ?: " ", fontSize = 11.sp, color = C.teal)
                }
            }
        }
    }
}

/** Kacheln wie WeatherDetailGrid in iOS; fehlende Werte (etwa Feuchte in der Vorhersage) entfallen. */
@Composable
private fun DetailGrid(h: WeatherHour, w: WeatherDay, air: List<AirHour>) {
    data class Tile(val label: String, val value: String, val icon: ImageVector, val caption: String? = null)
    val tiles = listOfNotNull(
        h.windSpeed?.let { Tile("Wind", "${it.roundToInt()} km/h", Icons.Default.Air,
            listOfNotNull(h.windDirection?.let { d -> "aus ${listOf("N", "NO", "O", "SO", "S", "SW", "W", "NW")[(((d % 360) + 382.5) / 45).toInt() % 8]}" },
                h.gust?.let { g -> "Böen ${g.roundToInt()}" }).joinToString(" · ")) },
        Tile("Regen", "${"%.1f".format(Town.locale, h.precipitation ?: 0.0)} mm", Icons.Default.WaterDrop, "Tag: ${"%.1f".format(Town.locale, w.rain)} mm"),
        Tile("Sonne", "${(h.sunshine ?: 0.0).roundToInt()} min", Icons.Default.WbSunny, "Tag: ${"%.1f".format(Town.locale, w.hours.mapNotNull { it.sunshine }.sum() / 60)} h"),
        h.cloudCover?.let { Tile("Wolken", "${it.roundToInt()} %", Icons.Default.Cloud, h.label) },
        h.humidity?.let { Tile("Luftfeuchte", "${it.roundToInt()} %", Icons.Default.WaterDrop, h.pressure?.let { p -> "${p.roundToInt()} hPa" }) },
        h.pressure?.takeIf { h.humidity == null }?.let { Tile("Luftdruck", "${it.roundToInt()} hPa", Icons.Default.Speed) },
        // Luftqualität der Stunde (UBA), nur mit dem Baustein `air`.
        air.minByOrNull { kotlin.math.abs(java.time.Duration.between(it.start, h.time).toMinutes()) }
            ?.takeIf { kotlin.math.abs(java.time.Duration.between(it.start, h.time).toMinutes()) <= 45 }?.let { Tile("Luft", it.label, Icons.Default.Masks) },
    )
    Column(verticalArrangement = Arrangement.spacedBy(Spacing)) {
        tiles.chunked(2).forEach { row ->
            Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                row.forEach { t ->
                    StedeCard(Modifier.weight(1f).fillMaxHeight(), padding = 14.dp) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(t.icon, null, tint = C.secondary, modifier = Modifier.size(16.dp)); Text(t.label, fontSize = 13.sp, color = C.secondary)
                        }
                        Text(t.value, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = C.text, modifier = Modifier.padding(top = 6.dp))
                        t.caption?.takeIf { it.isNotEmpty() }?.let { Text(it, fontSize = 12.sp, color = C.secondary, maxLines = 1) }
                    }
                }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun DayChart(w: WeatherDay, selected: WeatherHour) {
    val temps = w.hours.map { it.temperature }
    val rain = w.hours.map { it.precipitation ?: 0.0 }
    val lo = (temps.filterNotNull().minOrNull() ?: 0.0) - 1; val hi = (temps.filterNotNull().maxOrNull() ?: 1.0) + 1
    val maxRain = maxOf(rain.maxOrNull() ?: 0.0, 2.0)
    val line = C.amber; val bars = C.teal; val marker = C.ink
    val index = w.hours.indexOfFirst { it.timestamp == selected.timestamp }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text("Max ${temp(w.max)} · Min ${temp(w.min)}", fontSize = 12.sp, color = C.secondary)
        Text("${selected.time.format(Town.hm)}: ${temp(selected.temperature)}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = C.text)
    }
    Canvas(Modifier.fillMaxWidth().height(140.dp).padding(top = 8.dp)) {
        if (temps.isEmpty()) return@Canvas
        val step = size.width / (temps.size - 1).coerceAtLeast(1)
        rain.forEachIndexed { i, r ->
            val h = (r / maxRain * size.height * 0.5).toFloat()
            drawRect(bars.copy(alpha = 0.45f), Offset(i * step - step * 0.3f, size.height - h), Size(step * 0.6f, h))
        }
        val path = Path(); var started = false
        temps.forEachIndexed { i, t ->
            t ?: return@forEachIndexed
            val y = (size.height - (t - lo) / (hi - lo) * size.height).toFloat()
            if (!started) { path.moveTo(i * step, y); started = true } else path.lineTo(i * step, y)
        }
        drawPath(path, line, style = Stroke(width = 3.dp.toPx()))
        // Gewählte Stunde wie in iOS markiert.
        if (index >= 0) {
            drawLine(marker.copy(alpha = 0.5f), Offset(index * step, 0f), Offset(index * step, size.height), strokeWidth = 1.5.dp.toPx())
            temps[index]?.let { t -> drawCircle(line, 5.dp.toPx(), Offset(index * step, (size.height - (t - lo) / (hi - lo) * size.height).toFloat())) }
        }
    }
    Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        listOf("0", "6", "12", "18", "24").forEach { Text(it, fontSize = 11.sp, color = C.secondary) }
    }
}
