package de.letzgo.stede.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Duration
import java.time.LocalDate
import java.time.ZonedDateTime
import kotlin.math.cos

// Bausteine der Inseln: Fähre, Gezeiten mit Pegel, Luftqualität — wie FerryClient, TideStore,
// WaterLevelClient und AirQualityClient in iOS. Alle Kennungen kommen aus `tenants.config`.

// MARK: Fähre

data class FerryTrip(
    val number: Int, val departure: ZonedDateTime, val arrival: ZonedDateTime, val from: String,
    val excursion: Boolean, val vessel: String, val cancelled: Boolean, val occupancy: Int?, val toIsland: Boolean,
)

@Serializable private data class FerryTripDto(
    val fahrtnummer: Int, val abfahrt: String, val ankunft: String, val ausgangshafen: String,
    val ausflug: Boolean = false, val fahrzeugtyp: String = "", val fahrzeug: String? = null, val ausgefallen: Boolean = false,
    @SerialName("auslastung_personen") val auslastung: Int? = null,
)

object Ferry {
    /** Fahrten beider Richtungen eines Tages, nach Abfahrt sortiert. */
    suspend fun trips(day: LocalDate): List<FerryTrip> {
        val ferry = Tenants.config.ferry ?: return emptyList()
        val byId = linkedMapOf<Int, FerryTrip>()
        for (route in ferry.routes) {
            val rows = Http.json.decodeFromString<List<FerryTripDto>>(Http.text("https://api.langeoog.de/fahrten/$route/$day"))
            rows.forEach { r ->
                val dep = Town.parse(r.abfahrt) ?: return@forEach
                byId[r.fahrtnummer] = FerryTrip(r.fahrtnummer, dep, Town.parse(r.ankunft) ?: dep, r.ausgangshafen, r.ausflug,
                    r.fahrzeug ?: r.fahrzeugtyp, r.ausgefallen, r.auslastung, r.ausgangshafen == ferry.mainland)
            }
        }
        return byId.values.sortedBy { it.departure }
    }
}

// MARK: Gezeiten

data class TideEvent(val time: ZonedDateTime, /** Meter über Seekartennull. */ val height: Double, val high: Boolean, val phase: String?) {
    val label get() = if (high) "Hochwasser" else "Niedrigwasser"
    val phaseLabel get() = when (phase) { "SP" -> "Springzeit"; "NP" -> "Nippzeit"; "MT" -> "Mittzeit"; else -> null }
}

data class WaterLevel(val time: ZonedDateTime, val value: Double)

object Tides {
    /** Differenz Pegelnullpunkt minus Seekartennull, wie im Kalender auf langeoog.de. */
    private const val PNP_MINUS_SKN = 3.17
    fun fromPegel(cm: Double) = cm / 100 - PNP_MINUS_SKN
    fun meters(v: Double) = String.format(Town.locale, "%.2f m", v)

    private var cached: Pair<String, List<TideEvent>>? = null

    /** Vorausberechnung aus dem Bucket `content` (Server kürzt den BSH-Feed täglich); offline der letzte Stand. */
    suspend fun events(): List<TideEvent> {
        val slug = Tenants.slug
        cached?.takeIf { it.first == slug }?.let { return it.second }
        val config = Tenants.config.tides ?: return emptyList()
        val local = Store.read(Tenants.folder("tides"), "tides.json")
        val needsDownload = local == null || parse(local).lastOrNull()?.time?.isBefore(Town.now().plusDays(120)) != false
        val text = if (needsDownload) runCatching { Http.direct("${Backend.URL}/storage/v1/object/public/content/${config.path}") }
            .onSuccess { Store.write(Tenants.folder("tides"), "tides.json", it) }.getOrNull() ?: local else local
        val events = text?.let(::parse).orEmpty()
        if (events.isNotEmpty()) cached = slug to events
        return events
    }

    fun cachedEvents(): List<TideEvent> = cached?.takeIf { it.first == Tenants.slug }?.second
        ?: Store.read(Tenants.folder("tides"), "tides.json")?.let(::parse).orEmpty()

    private fun parse(text: String): List<TideEvent> = runCatching {
        val root = Http.json.parseToJsonElement(text).jsonObject
        root["years"]!!.jsonArray.flatMap { box ->
            box.jsonObject.values.flatMap { year ->
                year.jsonObject["hwnw_prediction"]?.jsonObject?.get("data")?.jsonArray.orEmpty().mapNotNull { e ->
                    val o = e.jsonObject
                    val type = o["type"]?.jsonPrimitive?.contentOrNull
                    val time = Town.parse(o["timestamp"]?.jsonPrimitive?.contentOrNull?.replace(' ', 'T')) ?: return@mapNotNull null
                    val h = o["height"]?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
                    if (type != "HW" && type != "NW") null else TideEvent(time, fromPegel(h), type == "HW", o["phase"]?.jsonPrimitive?.contentOrNull)
                }
            }
        }.sortedBy { it.time }
    }.getOrDefault(emptyList())

    /** Kosinus-Verlauf zwischen zwei Scheiteln — wie TideCurve in iOS. */
    fun height(at: ZonedDateTime, events: List<TideEvent>): Double? {
        val i = events.indexOfLast { !it.time.isAfter(at) }
        if (i < 0 || i + 1 >= events.size) return null
        val l = events[i]; val r = events[i + 1]
        val span = Duration.between(l.time, r.time).seconds.toDouble()
        if (span <= 0) return l.height
        val p = Duration.between(l.time, at).seconds / span
        return (l.height + r.height) / 2 + (l.height - r.height) / 2 * cos(Math.PI * p)
    }

    fun curve(events: List<TideEvent>, day: LocalDate, stepMinutes: Long = 10): List<WaterLevel> {
        val start = day.atStartOfDay(Town.zone); val end = day.plusDays(1).atStartOfDay(Town.zone)
        return generateSequence(start) { it.plusMinutes(stepMinutes) }.takeWhile { !it.isAfter(end) }
            .mapNotNull { t -> height(t, events)?.let { WaterLevel(t, it) } }.toList()
    }

    @Serializable private data class LevelRow(val ts: String, val value: Double)

    /** Gemessene 10-Minuten-Mittel aus `water_levels` (PEGELONLINE, 31 Tage). */
    suspend fun measured(day: LocalDate): List<WaterLevel> {
        val gauge = Tenants.config.tides?.gauge ?: return emptyList()
        val from = day.atStartOfDay(Town.zone).toOffsetDateTime().toString(); val to = day.plusDays(1).atStartOfDay(Town.zone).toOffsetDateTime().toString()
        return Backend.supabase.from("water_levels").select(Columns.raw("ts,value")) {
            filter { eq("station", gauge); gte("ts", from); lte("ts", to) }
            order("ts", Order.ASCENDING); limit(1000)
        }.decodeList<LevelRow>().mapNotNull { r -> Town.parse(r.ts)?.let { WaterLevel(it, fromPegel(r.value)) } }
    }
}

// MARK: Luftqualität (Umweltbundesamt)

data class AirHour(val start: ZonedDateTime, val index: Int, val pollutants: List<Pair<Int, Double>>) {
    val label get() = when (index) { 1 -> "Sehr gut"; 2 -> "Gut"; 3 -> "Mäßig"; 4 -> "Schlecht"; 5 -> "Sehr schlecht"; else -> "Unbekannt" }
    /** PM10, PM2,5, NO₂, O₃ — in dieser Reihenfolge, wie iOS. */
    val display get() = listOf(1, 9, 5, 3).mapNotNull { id -> pollutants.firstOrNull { it.first == id } }
    companion object {
        fun name(id: Int) = when (id) { 1 -> "PM10"; 3 -> "O₃"; 4 -> "SO₂"; 5 -> "NO₂"; 9 -> "PM2,5"; else -> "Komponente $id" }
    }
}

object Air {
    suspend fun hours(day: LocalDate): List<AirHour> {
        val station = Tenants.config.airStation ?: return emptyList()
        val text = Http.text("https://luftdaten.umweltbundesamt.de/api-proxy/airquality/json?date_from=$day&date_to=$day&time_from=1&time_to=24&station=$station&lang=de")
        val data = Http.json.parseToJsonElement(text).jsonObject["data"]?.jsonObject ?: return emptyList()
        return data.values.flatMap { byStart ->
            (byStart as? JsonObject)?.entries.orEmpty().mapNotNull { (startRaw, raw) ->
                val fields = raw as? JsonArray ?: return@mapNotNull null
                if (fields.size < 3) return@mapNotNull null
                // UBA liefert Ortszeit ohne Zone (MEZ, +01:00).
                val start = runCatching { java.time.LocalDateTime.parse(startRaw.replace(' ', 'T')).atOffset(java.time.ZoneOffset.ofHours(1)).atZoneSameInstant(Town.zone) }.getOrNull() ?: return@mapNotNull null
                val index = fields[1].jsonPrimitive.intOrNull ?: 0
                val pollutants = fields.drop(3).mapNotNull { item ->
                    val row = item as? JsonArray ?: return@mapNotNull null
                    val id = row.getOrNull(0)?.jsonPrimitive?.intOrNull ?: return@mapNotNull null
                    val value = row.getOrNull(1)?.jsonPrimitive?.doubleOrNull ?: return@mapNotNull null
                    id to value
                }
                AirHour(start, index, pollutants)
            }
        }.sortedBy { it.start }
    }
}
