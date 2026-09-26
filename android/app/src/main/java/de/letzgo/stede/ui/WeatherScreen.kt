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
    LaunchedEffect(day) {
        weather = Weather.cached(day); error = null; selectedHour = null
        runCatching { Weather.load(day) }.onSuccess { weather = it }.onFailure { if (weather == null) error = it.message }
    }
    val w = weather
    val current = w?.let { if (day == Town.today()) it.current() else it.hours.firstOrNull { h -> h.time.hour == 12 } ?: it.hours.firstOrNull() }
    val selected = w?.hours?.firstOrNull { it.timestamp == selectedHour } ?: current
    Scaffold(topBar = { StedeTopBar("Wetter", onBack) }, containerColor = C.sand) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                if (w == null) { item { if (error != null) InfoCard(error!!) else Loading() }; return@LazyColumn }
                item {
                    StedeCard(highlighted = true) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Icon(weatherIcon(current?.icon, current?.condition), null, tint = C.teal, modifier = Modifier.size(56.dp))
                            Column(Modifier.weight(1f)) {
                                Text(temp(current?.temperature), fontSize = 44.sp, fontWeight = FontWeight.Bold, color = C.text)
                                Text(current?.label ?: "", color = C.secondary)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text("Max ${temp(w.max)}", color = C.text, fontWeight = FontWeight.SemiBold)
                                Text("Min ${temp(w.min)}", color = C.secondary)
                                Text("%.1f mm".format(Town.locale, w.rain), color = C.secondary, fontSize = 13.sp)
                            }
                        }
                    }
                }
                item { SectionHeader("Stündlich", Icons.Default.Schedule) }
                item {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(w.hours) { h ->
                            val chosen = h.timestamp == selected?.timestamp
                            Column(Modifier.width(58.dp).background(if (chosen) C.teal.copy(alpha = 0.2f) else C.surface, CardShape).clickable { selectedHour = h.timestamp }.padding(vertical = 10.dp),
                                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(h.time.format(Town.fmt("HH")), fontSize = 13.sp, color = C.secondary)
                                Icon(weatherIcon(h.icon, h.condition), null, tint = C.teal, modifier = Modifier.size(22.dp))
                                Text(temp(h.temperature), fontWeight = FontWeight.SemiBold, color = C.text)
                                if ((h.precipitation ?: 0.0) > 0) Text("%.1f".format(Town.locale, h.precipitation), fontSize = 11.sp, color = C.teal)
                            }
                        }
                    }
                }
                item { SectionHeader("Tagesverlauf", Icons.Default.ShowChart) }
                item { StedeCard { DayChart(w) } }
                selected?.let { h ->
                    item { SectionHeader("Details um ${h.time.format(Town.hm)}", Icons.Default.GridView) }
                    item {
                        val tiles = listOf(
                            Triple("Wind", h.windSpeed?.let { "${it.roundToInt()} km/h" } ?: "–", Icons.Default.Air),
                            Triple("Böen", h.gust?.let { "${it.roundToInt()} km/h" } ?: "–", Icons.Default.Storm),
                            Triple("Feuchte", h.humidity?.let { "${it.roundToInt()} %" } ?: "–", Icons.Default.WaterDrop),
                            Triple("Luftdruck", h.pressure?.let { "${it.roundToInt()} hPa" } ?: "–", Icons.Default.Speed),
                            Triple("Bewölkung", h.cloudCover?.let { "${it.roundToInt()} %" } ?: "–", Icons.Default.Cloud),
                            Triple("Sonne", h.sunshine?.let { "${it.roundToInt()} min" } ?: "–", Icons.Default.WbSunny),
                        )
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing)) {
                            tiles.chunked(2).forEach { row ->
                                Row(horizontalArrangement = Arrangement.spacedBy(Spacing)) {
                                    row.forEach { (label, value, icon) ->
                                        StedeCard(Modifier.weight(1f)) {
                                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) { Icon(icon, null, tint = C.secondary, modifier = Modifier.size(16.dp)); Text(label, fontSize = 13.sp, color = C.secondary) }
                                            Text(value, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = C.text, modifier = Modifier.padding(top = 4.dp))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                item { SourceFooter("Deutscher Wetterdienst über Bright Sky${w.station?.let { " · Station $it" } ?: ""}") }
            }
            DayBar(day, latest = Town.today().plusDays(9), modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp)) { day = it }
        }
    }
}

@Composable
private fun DayChart(w: WeatherDay) {
    val temps = w.hours.map { it.temperature }
    val rain = w.hours.map { it.precipitation ?: 0.0 }
    val lo = (temps.filterNotNull().minOrNull() ?: 0.0) - 1; val hi = (temps.filterNotNull().maxOrNull() ?: 1.0) + 1
    val maxRain = maxOf(rain.maxOrNull() ?: 0.0, 2.0)
    val line = C.amber; val bars = C.teal
    Canvas(Modifier.fillMaxWidth().height(140.dp)) {
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
    }
    Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        listOf("0", "6", "12", "18", "24").forEach { Text(it, fontSize = 11.sp, color = C.secondary) }
    }
}
