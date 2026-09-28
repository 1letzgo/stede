package de.letzgo.stede.data

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

// MARK: Bahn — dbf.finalrewind.org (DB IRIS), wie TrainClient in iOS

/**
 * Fahrtrichtung ab einem Ammerland-Bahnhof — jede Strecke hat zwei Enden: Oldenburg und die Gegenrichtung
 * (Leer, ab Rastede Wilhelmshaven). Gespeichert als „oldenburg“/„leer“ wie in iOS; die Namen kommen vom Bahnhof.
 */
enum class TrainDirection {
    Oldenburg, Leer;

    /** „Oldenburg“, „Leer“ oder „Wilhelmshaven“ — je nach Bahnhof. */
    fun short(station: TenantStation?): String = when (this) {
        Oldenburg -> station?.directions?.getOrNull(0) ?: "Oldenburg"
        Leer -> station?.directions?.getOrNull(1) ?: "Leer"
    }
    fun title(station: TenantStation?) = "Richtung ${short(station)}"

    companion object {
        /** Gespeicherte Richtung (`train.direction`), sonst Oldenburg. */
        fun stored() = runCatching { valueOf(Store.string("train.direction", "oldenburg").replaceFirstChar { it.uppercase() }) }.getOrDefault(Oldenburg)
    }
}

data class Train(
    val id: String, val scheduled: ZonedDateTime, val delay: Int, val platform: String?, val scheduledPlatform: String?,
    val line: String, val destination: String, val via: List<String>, val direction: TrainDirection, val cancelled: Boolean, val notes: List<String>,
) { val departure get() = scheduled.plusMinutes(delay.toLong()); val platformChanged get() = platform != null && scheduledPlatform != null && platform != scheduledPlatform }

@Serializable private data class DbfStop(val name: String = "")
@Serializable private data class DbfMessage(val text: String? = null)
@Serializable private data class DbfMessages(val delay: List<DbfMessage> = emptyList(), val qos: List<DbfMessage> = emptyList())
@Serializable private data class DbfDeparture(
    val scheduledDeparture: String? = null, val delayDeparture: Int? = null, val platform: String? = null, val scheduledPlatform: String? = null,
    val destination: String = "", val train: String = "", val trainNumber: String? = null, val isCancelled: JsonElement? = null,
    val route: List<DbfStop> = emptyList(), val via: List<String> = emptyList(), val messages: DbfMessages? = null,
)
@Serializable private data class DbfBoard(val departures: List<DbfDeparture> = emptyList())

object Trains {
    private var board: List<Train> = emptyList()
    private var fetchedAt = 0L
    private var stationId: String? = null

    /** Gewählter Bahnhof (`train.station`), sonst der Standardbahnhof der Gemeinde. */
    fun station(): TenantStation? = Tenants.config.station(Store.string("train.station", ""))

    /** Zuletzt geladene Tafel dieses Bahnhofs, auch wenn sie schon älter ist. */
    fun cached(station: TenantStation?): List<Train> = if (station != null && station.id == stationId) board else emptyList()

    suspend fun load(station: TenantStation, force: Boolean = false): List<Train> {
        if (!force && station.id == stationId && System.currentTimeMillis() - fetchedAt < 60_000 && board.isNotEmpty()) return board
        val name = java.net.URLEncoder.encode(station.dbf, "UTF-8").replace("+", "%20")
        val raw = Http.json.decodeFromString<DbfBoard>(Http.text("https://dbf.finalrewind.org/$name.json?version=3"))
        val now = Town.now()
        val list = raw.departures.mapNotNull { d ->
            val time = d.scheduledDeparture ?: return@mapNotNull null
            val parts = time.split(":"); if (parts.size != 2) return@mapNotNull null
            var scheduled = now.toLocalDate().atTime(parts[0].toInt(), parts[1].toInt()).atZone(Town.zone)
            if (scheduled.isBefore(now.minusHours(6))) scheduled = scheduled.plusDays(1)
            val stops = d.route.map { it.name }
            val after = stops.indexOf(station.name).let { if (it >= 0) stops.drop(it + 1) else d.via }
            val joined = (after + d.destination).joinToString(" ").lowercase()
            // Alles Richtung Oldenburg (und weiter nach Bremen, Hannover, Osnabrück) ist Oldenburg, der Rest die Gegenrichtung.
            val direction = when {
                listOf("oldenburg", "bremen", "hannover", "osnabrück", "osnabrueck").any { it in joined } -> TrainDirection.Oldenburg
                listOf("leer", "emden", "norddeich", "augustfehn", "wilhelmshaven", "varel", "sande", "jever", "esens").any { it in joined } -> TrainDirection.Leer
                else -> return@mapNotNull null
            }
            val cancelled = (d.isCancelled as? JsonPrimitive)?.let { it.booleanOrNull ?: (it.intOrNull == 1) } ?: false
            val p = d.train.split(" ")
            val line = if (p.size == 2 && p[1].startsWith(p[0])) p[1] else d.train
            val notes = ((d.messages?.delay ?: emptyList()) + (d.messages?.qos ?: emptyList())).mapNotNull { it.text?.trim()?.ifBlank { null } }.take(2)
            Train("${d.trainNumber ?: d.train}-$time", scheduled, d.delayDeparture ?: 0, d.platform, d.scheduledPlatform, line, d.destination, after.take(3), direction, cancelled, notes)
        }
        // IC mit Nahverkehrsfreigabe steht doppelt auf der Tafel: RE-Zeile behalten, IC-Nummer anhängen.
        board = list.groupBy { "${it.scheduled}|${it.destination}" }.values.map { g ->
            val re = g.firstOrNull { it.line.startsWith("RE") }; val ic = g.firstOrNull { !it.line.startsWith("RE") }
            if (g.size > 1 && re != null && ic != null) re.copy(line = "${re.line} · ${ic.line}", delay = maxOf(re.delay, ic.delay), notes = re.notes.ifEmpty { ic.notes }) else g.first()
        }.sortedBy { it.scheduled }
        stationId = station.id
        fetchedAt = System.currentTimeMillis()
        return board
    }
}

// MARK: Bus — VBN-Fahrplaner (HAFAS stboard.exe, vs_java3), wie BusClient in iOS

/** Haltestelle; der Kurzname lässt den Gemeindenamen davor weg („ZOB“ statt „Westerstede ZOB“). */
data class BusStop(val id: String, val name: String) {
    val short: String get() = Tenants.config.municipality.let { town -> name.replace("$town-", "").replace("$town ", "") }
}

private var loadedStops: Pair<String, List<BusStop>>? = null

/** Haltestellen der Gemeinde: Tabelle `bus_stops`, sonst `content_files` (`bus-stops.json`), sonst (nur Westerstede) die Liste unten. */
val busStops: List<BusStop>
    get() = loadedStops?.takeIf { it.first == Tenants.slug }?.second ?: (
        listOfNotNull(Store.read(Tenants.folder("content"), "bus-stops.json"), ContentFiles.text("bus-stops")).firstNotNullOfOrNull { text ->
            runCatching {
                Http.json.parseToJsonElement(text).jsonObject["stops"]!!.jsonArray.map {
                    val o = it.jsonObject
                    BusStop(o["id"]!!.jsonPrimitive.content, o["name"]!!.jsonPrimitive.content)
                }
            }.getOrNull()?.takeIf { it.isNotEmpty() }
        } ?: if (Tenants.usesBundle) bundledBusStops else emptyList()
        ).also { loadedStops = Tenants.slug to it }

private val bundledBusStops = listOf(
    BusStop("009098661", "Westerstede ZOB"), BusStop("009098621", "Westerstede Altenheim"), BusStop("009098630", "Westerstede Am Esch"),
    BusStop("009098623", "Westerstede Ammerland-Klinik"), BusStop("009098624", "Westerstede Amtsgericht"), BusStop("009060998", "Westerstede An der Norderbäke"),
    BusStop("009098628", "Westerstede Brakenhoffschule"), BusStop("009098631", "Westerstede Detershof"), BusStop("009098627", "Westerstede Eichendorffstraße"),
    BusStop("009098633", "Westerstede Famila"), BusStop("009098634", "Westerstede Finanzamt"), BusStop("009098637", "Westerstede Goethestraße"),
    BusStop("009098639", "Westerstede Gymnasium"), BusStop("009098641", "Westerstede Hössenbad"), BusStop("009098644", "Westerstede Kreishaus"),
    BusStop("009098645", "Westerstede Kuhlenstraße"), BusStop("009098647", "Westerstede Lüttje Moorpadd"), BusStop("009098651", "Westerstede Oberschule"),
    BusStop("009098655", "Westerstede Süderstraße/Virchowstraße"), BusStop("009098657", "Westerstede Telekom"), BusStop("009098666", "Westerstede-Lindern Rosenkrug"),
    BusStop("009098668", "Westerstede-Ocholt Bahnhof"),
)
/** Die gewählte Haltestelle, sonst die Standardhaltestelle der Gemeinde. */
fun busStop(id: String): BusStop {
    val stops = busStops; val fallback = Tenants.config.busDefaultStop
    return stops.firstOrNull { it.id == id } ?: stops.firstOrNull { it.id == fallback } ?: stops.firstOrNull() ?: BusStop(fallback, Tenants.config.municipality)
}

data class Bus(val id: String, val scheduled: ZonedDateTime, val delay: Int?, val line: String, val destination: String, val platform: String?, val cancelled: Boolean) {
    val departure: ZonedDateTime get() = scheduled.plusMinutes((delay ?: 0).toLong())
}

object Buses {
    private val cache = mutableMapOf<String, Pair<Long, List<Bus>>>()
    private val journey = Regex("""<Journey\s([^>]*?)/>""", RegexOption.DOT_MATCHES_ALL)
    private val attr = Regex("""(\w+)="([^"]*)"""")
    private val dateFmt = DateTimeFormatter.ofPattern("dd.MM.yy HH:mm")

    fun cached(stop: BusStop, day: LocalDate) = cache["${stop.id}|$day"]?.second

    suspend fun load(stop: BusStop, day: LocalDate, force: Boolean = false): List<Bus> {
        val key = "${stop.id}|$day"
        cache[key]?.let { if (!force && System.currentTimeMillis() - it.first < 60_000) return it.second }
        val all = linkedMapOf<String, Bus>()
        var from = day.atStartOfDay(Town.zone)
        repeat(4) {
            val url = "https://fahrplaner.vbn.de/bin/stboard.exe/dn?input=${stop.id}&boardType=dep&date=${from.format(DateTimeFormatter.ofPattern("dd.MM.yy"))}&time=${from.format(Town.hm)}&maxJourneys=120&start=yes&L=vs_java3"
            val page = parse(Http.text(url))
            page.forEach { all.putIfAbsent(it.id, it) }
            val last = page.lastOrNull()?.scheduled
            if (page.size < 120 || last == null || last.toLocalDate() != day || !last.isAfter(from)) return@repeat
            from = last.plusMinutes(1)
        }
        val list = all.values.filter { it.scheduled.toLocalDate() == day }.sortedBy { it.scheduled }
        cache[key] = System.currentTimeMillis() to list
        return list
    }

    private fun unescape(s: String) = Regex("&#(\\d+);").replace(s.replace("&amp;", "&").replace("&quot;", "\"")) { String(Character.toChars(it.groupValues[1].toInt())) }

    fun parse(xml: String): List<Bus> = journey.findAll(xml).mapNotNull { m ->
        val a = attr.findAll(m.groupValues[1]).associate { it.groupValues[1] to it.groupValues[2] }
        val time = a["fpTime"] ?: return@mapNotNull null; val date = a["fpDate"] ?: return@mapNotNull null
        val name = a["hafasname"] ?: return@mapNotNull null
        if (a["prod"]?.endsWith("#Bus") == false && !name.startsWith("Bus")) return@mapNotNull null
        val scheduled = runCatching { LocalDateTime.parse("$date $time", dateFmt).atZone(Town.zone) }.getOrNull() ?: return@mapNotNull null
        // Ziele in der Gemeinde ohne den Ortsnamen davor — Platz ist knapp.
        val town = Tenants.config.municipality + " "
        var dest = unescape(a["dir"] ?: a["targetLoc"] ?: ""); if (dest.startsWith(town)) dest = dest.removePrefix(town)
        val line = name.removePrefix("Bus ")
        val delay = a["delay"]?.toIntOrNull()
        Bus("$line-$date-$time-$dest", scheduled, delay, line, dest, a["platform"]?.ifBlank { null }, (a["delay"] ?: "").lowercase().contains("cancel"))
    }.toList()
}
