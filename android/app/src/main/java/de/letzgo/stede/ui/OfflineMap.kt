package de.letzgo.stede.ui

import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.Store
import de.letzgo.stede.data.ContentFiles
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.double
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min

/** Offline-Stadtkarte aus `inselkarte.json` (OpenStreetMap) — wie OfflineIslandMap in iOS. */
object MapData {
    private const val LAT0 = 53.26; private const val LON0 = 7.935
    private val kx = 111_320.0 * cos(Math.toRadians(LAT0)); private const val KY = 111_320.0
    fun x(lon: Double) = ((lon - LON0) * kx).toFloat()
    fun y(lat: Double) = (-(lat - LAT0) * KY).toFloat()

    class Layers(val polygons: Map<String, Path>, val lines: Map<String, Path>, val buildings: Path, val land: Path, val bounds: FloatArray)
    @Volatile private var loaded: Layers? = null

    suspend fun load(): Layers = loaded ?: withContext(Dispatchers.Default) {
        val root = Json.parseToJsonElement(ContentFiles.text("inselkarte") ?: Store.asset("inselkarte.json")).jsonObject
        fun rings(arr: JsonArray?, close: Boolean): Path {
            val path = Path()
            arr?.forEach { ring ->
                ring.jsonArray.forEachIndexed { i, p ->
                    val pt = p.jsonArray; val px = x(pt[0].jsonPrimitive.double); val py = y(pt[1].jsonPrimitive.double)
                    if (i == 0) path.moveTo(px, py) else path.lineTo(px, py)
                }
                if (close) path.close()
            }
            return path
        }
        val polys = root["polygons"]!!.jsonObject.mapValues { rings(it.value.jsonArray, true) }
        val lines = root["lines"]!!.jsonObject.mapValues { rings(it.value.jsonArray, false) }
        val land = root["land"]!!.jsonArray
        val lons = land.flatMap { r -> r.jsonArray.map { it.jsonArray[0].jsonPrimitive.double } }
        val lats = land.flatMap { r -> r.jsonArray.map { it.jsonArray[1].jsonPrimitive.double } }
        // Keine Einzelgebäude: die Siedlungsfläche reicht (spart Laden und Zeichnen der 11.000 Umrisse).
        Layers(polys, lines, Path(), rings(land, true),
            floatArrayOf(x(lons.min()), y(lats.max()), x(lons.max()), y(lats.min()))).also { loaded = it }
    }
}

data class MapPin(val id: String, val lat: Double, val lon: Double, val icon: ImageVector, val color: Color, val title: String)

@Composable
fun OfflineMap(pins: List<MapPin>, selectedId: String?, modifier: Modifier = Modifier, onSelect: (String) -> Unit) {
    var layers by remember { mutableStateOf<MapData.Layers?>(null) }
    LaunchedEffect(Unit) { layers = MapData.load() }
    var size by remember { mutableStateOf(IntSize.Zero) }
    var scale by remember { mutableFloatStateOf(0f) }        // Pixel je Meter
    var offset by remember { mutableStateOf(Offset.Zero) }   // Bildschirmlage des Kartenursprungs
    val density = LocalDensity.current

    fun clampScale(s: Float): Float {
        val b = layers?.bounds ?: return s
        val minS = max(size.width / (b[2] - b[0]), size.height / (b[3] - b[1]))
        return s.coerceIn(minS, size.width / 150f)
    }
    fun center(xw: Float, yw: Float) { offset = Offset(size.width / 2f - xw * scale, size.height / 2f - yw * scale) }

    // Erste Ansicht: Pins rund um den Markt, sonst alle.
    LaunchedEffect(size, layers, pins.map { it.id }) {
        if (size == IntSize.Zero || layers == null || pins.isEmpty() || scale != 0f) return@LaunchedEffect
        val near = pins.filter { kotlin.math.abs(it.lat - 53.257) < 0.01 && kotlin.math.abs(it.lon - 7.927) < 0.02 }.ifEmpty { pins }
        val xs = near.map { MapData.x(it.lon) }; val ys = near.map { MapData.y(it.lat) }
        val w = max(xs.max() - xs.min(), 400f) * 1.4f; val h = max(ys.max() - ys.min(), 400f) * 1.6f
        scale = clampScale(min(size.width / w, size.height / h))
        center((xs.max() + xs.min()) / 2, (ys.max() + ys.min()) / 2)
    }
    // Auswahl aus der Liste zentriert die Karte.
    LaunchedEffect(selectedId) {
        val p = pins.firstOrNull { it.id == selectedId } ?: return@LaunchedEffect
        if (scale == 0f) return@LaunchedEffect
        scale = clampScale(max(scale, size.width / 900f)); center(MapData.x(p.lon), MapData.y(p.lat))
    }

    val sand = C.sand; val ground = C.mudflat.copy(alpha = 0.12f); val mud = C.mudflat; val green = C.green; val teal = C.teal; val ink = C.ink; val red = C.red
    Box(modifier.clip(CardShape).background(sand).onSizeChanged { size = it }
        .pointerInput(layers) {
            detectTransformGestures { centroid, pan, zoom, _ ->
                if (scale == 0f) return@detectTransformGestures
                val ns = clampScale(scale * zoom)
                offset = centroid - (centroid - offset) * (ns / scale) + pan
                scale = ns
            }
        }) {
        val l = layers
        if (l != null && scale > 0f) {
            Canvas(Modifier.fillMaxSize()) {
                drawIntoCanvas { c ->
                    val cv = c.nativeCanvas
                    cv.drawColor(ground.toArgb())
                    cv.save(); cv.translate(offset.x, offset.y); cv.scale(scale, scale)
                    fun fill(path: Path?, color: Color) { path ?: return; cv.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; this.color = color.toArgb() }) }
                    fun line(path: Path?, color: Color, widthDp: Float, dashed: Boolean = false) {
                        path ?: return
                        val w = widthDp * density.density / scale
                        cv.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            style = Paint.Style.STROKE; strokeWidth = w; this.color = color.toArgb(); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
                            if (dashed) pathEffect = DashPathEffect(floatArrayOf(w * 3, w * 2.5f), 0f)
                        })
                    }
                    fill(l.land, sand)
                    fill(l.polygons["settlement"], mud.copy(alpha = 0.16f))
                    fill(l.polygons["green"], green.copy(alpha = 0.16f))
                    fill(l.polygons["wood"], green.copy(alpha = 0.40f))
                    fill(l.polygons["water"], teal.copy(alpha = 0.45f))
                    line(l.lines["stream"], teal.copy(alpha = 0.55f), 1.2f)
                    if (scale > size.width / 5000f) line(l.lines["path"], ink.copy(alpha = 0.28f), 1f, dashed = true)
                    line(l.lines["road"], ink.copy(alpha = 0.38f), 2.2f)
                    line(l.lines["rail"], red.copy(alpha = 0.6f), 1.5f, dashed = true)
                    cv.restore()
                }
            }
            pins.forEach { p ->
                val chosen = p.id == selectedId
                val px = offset.x + MapData.x(p.lon) * scale; val py = offset.y + MapData.y(p.lat) * scale
                val sz = if (chosen) 40.dp else 30.dp
                val half = with(density) { (sz / 2).roundToPx() }
                if (px < -half || py < -half || px > size.width + half || py > size.height + half) return@forEach
                Box(Modifier.offset { IntOffset(px.toInt() - half, py.toInt() - half * 2) }.size(sz).clip(CircleShape)
                    .background(if (chosen) Color.White else p.color).border(if (chosen) 3.dp else 2.dp, if (chosen) p.color else Color.White, CircleShape)
                    .clickable { onSelect(p.id) }, contentAlignment = Alignment.Center) {
                    Icon(p.icon, p.title, tint = if (chosen) p.color else Color.White, modifier = Modifier.size(sz * 0.55f))
                }
            }
        }
        Text("© OpenStreetMap", fontSize = 10.sp, color = C.secondary, modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp)
            .background(C.surface.copy(alpha = 0.8f), RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 2.dp))
    }
}
