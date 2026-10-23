package de.letzgo.stede.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject

@Serializable data class Tenant(val id: String, val slug: String, val name: String, val municipality: String)

/** Bahnhof im Ammerland: EVA-Nummer, Name im Abfahrtsmonitor, Anzeigename, [Richtung Oldenburg, Gegenrichtung]. */
@Serializable data class TenantStation(val id: String, val dbf: String, val name: String, val directions: List<String> = emptyList())

/**
 * Eine Gemeinde im Ammerland mit allem, was die App je Gemeinde anders macht
 * (`tenants.config` im Backend, Erststand in `assets/tenants.json`) — wie TenantConfig in iOS.
 */
@Serializable data class TenantConfig(
    val slug: String,
    val municipality: String,
    /** [Breite, Länge] des Ortskerns — Wetter und Kartenmitte. */
    val center: List<Double>,
    /** [Süd, West, Nord, Ost] — Kartenausschnitt. */
    val bbox: List<Double>,
    /** Gemeinden ohne Bahn, Bus oder Abfuhr lassen deren Felder weg. */
    val stations: List<TenantStation> = emptyList(),
    val defaultStation: String = "",
    val wasteTownID: Int = 0,
    val busDefaultStop: String = "",
    /** `tenants.id` — für Termine, die nur in bestimmten Gemeinden erscheinen. */
    val tenantID: String? = null,
    /** `tenants.region` — welche App die Gemeinde zeigt ([Brand.region]). */
    val region: String? = null,
    /** Bausteine; null = Standard der Marke ([Features]). */
    val features: FeatureSet? = null,
    val ferry: FerryConfig? = null,
    val tides: TideConfig? = null,
    /** UBA-Messstation für die Luftqualität, etwa „DENI058“. */
    val airStation: String? = null,
    /** Hinweise unter Ortslisten und im Kalender je Schlüssel (`health`, `trips`, `events`). */
    val notes: Map<String, String>? = null,
    /** Kacheln „Externe Anbieter“ auf Start. */
    val external: List<ExternalLink>? = null,
    /** Ratsinformationssystem (Baustein `politics`). */
    val ris: RisConfig? = null,
    /** Seepunkt vor der Insel für Wind und Seegang (`marine_forecasts`). */
    val marine: MarineConfig? = null,
) {
    val latitude get() = center.getOrElse(0) { 53.2575 }
    val longitude get() = center.getOrElse(1) { 7.9273 }

    fun station(id: String?): TenantStation? =
        stations.firstOrNull { it.id == id } ?: stations.firstOrNull { it.id == defaultStation } ?: stations.firstOrNull()

    /** „Stadt Westerstede“, sonst „Gemeinde …“. */
    val officialName get() = if (slug == Tenants.BUNDLE) "Stadt $municipality" else "Gemeinde $municipality"
}

/**
 * Fähre: `type` „api“ (Standard, api.langeoog.de mit `routes` „von/nach“ und `mainland`-Hafenkürzel) oder „pdf“ —
 * fester Fahrplan, den `sync-ferry-pdf` aus dem PDF der Reederei als Datei `file` ablegt; `vessels` Kürzel → Name.
 */
@Serializable data class FerryConfig(
    val type: String? = null, val routes: List<String> = emptyList(), val mainland: String = "",
    val file: String? = null, val vessels: Map<String, String> = emptyMap(),
    @SerialName("mainland_name") val mainlandName: String, @SerialName("island_name") val islandName: String,
    @SerialName("booking_url") val bookingUrl: String? = null, val source: String? = null,
)

/** Gezeiten als Datei im Bucket `content` (`path`), gemessene Pegel aus `water_levels` (`gauge`). */
@Serializable data class TideConfig(
    val file: String, val path: String, val gauge: String? = null, @SerialName("gauge_name") val gaugeName: String = "",
)

@Serializable data class ExternalLink(val title: String, val symbol: String, val url: String)

/** ALLRIS-net-Bürgerinfo der Gemeinde, `{"url": "https://ris.westerstede.de/bi/"}`. */
@Serializable data class RisConfig(val url: String)

/** `{"lat": 53.80, "lon": 7.48, "name": "Seegebiet vor Langeoog"}`. */
@Serializable data class MarineConfig(val lat: Double, val lon: Double, val name: String? = null)

@Serializable private data class TenantRow(val id: String, val slug: String, val municipality: String, val config: JsonObject)
@Serializable private data class TenantRowConfig(
    val center: List<Double>? = null, val bbox: List<Double>? = null, val stations: List<TenantStation>? = null,
    @SerialName("default_station") val defaultStation: String? = null,
    @SerialName("waste_town_id") val wasteTownId: Int? = null,
    @SerialName("bus_default_stop") val busDefaultStop: String? = null,
    val features: FeatureSet? = null, val ferry: FerryConfig? = null, val tides: TideConfig? = null,
    @SerialName("air_station") val airStation: String? = null, val notes: Map<String, String>? = null, val external: List<ExternalLink>? = null,
    val ris: RisConfig? = null,
    val marine: MarineConfig? = null,
)

/**
 * Welche Gemeinde die App gerade zeigt — wie Tenants in iOS. Die Wahl liegt in den Einstellungen
 * (`tenant.slug`); Stände je Gemeinde liegen in getrennten Ordnern, Westerstede behält die alten.
 */
object Tenants {
    /** Gemeinde der Marke; ihre Inhalte liegen in den alten Ordnern ohne Unterordner. */
    val DEFAULT get() = Brand.current.defaultTenant
    /** Gemeinde, deren Daten in den Assets liegen (Westerstede, nur im stede-Flavor). */
    const val BUNDLE = "stede"
    const val KEY = "tenant.slug"
    /** Wird die Gemeinde gewechselt, gelten diese Einstellungen nicht mehr. */
    private val perTenantKeys = listOf("bus.stop", "train.station", "train.direction", "waste.street", "waste.section", "waste.branchSection", "waste.noOrganic", "waste.fourWeekly")
    private val listSerializer = ListSerializer(TenantConfig.serializer())

    /** Gewählte Gemeinde; null, solange beim ersten Start noch keine gewählt ist. Compose beobachtet den Wert. */
    var chosen by mutableStateOf(if (Brand.current.choosesTenant) Store.prefs.getString(KEY, null) else Brand.current.defaultTenant.also { migrateToDefault() }); private set

    /** Seit 10/2026 kennt stede nur Westerstede: eine früher gewählte andere Gemeinde samt Straße, Haltestelle und Bahnhof verwerfen. */
    private fun migrateToDefault() {
        val stored = Store.prefs.getString(KEY, null) ?: return
        if (stored == Brand.current.defaultTenant) return
        val edit = Store.prefs.edit().putString(KEY, Brand.current.defaultTenant)
        perTenantKeys.forEach { edit.remove(it) }
        edit.apply()
    }

    val slug: String get() = chosen ?: DEFAULT
    val hasChosen get() = chosen != null
    /** Westerstede hat die Daten in den Assets; alle anderen nur aus dem Backend. */
    val usesBundle get() = slug == BUNDLE

    private val bundled: List<TenantConfig> by lazy {
        runCatching { Http.json.decodeFromString(listSerializer, Store.asset("tenants.json")) }.getOrNull()
            ?.filter { it.region == Brand.current.region }?.takeIf { it.isNotEmpty() }
            ?: listOf(TenantConfig(BUNDLE, "Westerstede", listOf(53.25752, 7.92734), listOf(53.15, 7.78, 53.36, 8.10),
                listOf(TenantStation("8004610", "Westerstede-Ocholt", "Westerstede-Ocholt", listOf("Oldenburg", "Leer"))), "8004610", 5, "009098661"))
    }
    private var remote: List<TenantConfig>? = null

    val all: List<TenantConfig>
        get() = remote ?: Store.read("content", "tenants.json")?.let { runCatching { Http.json.decodeFromString(listSerializer, it) }.getOrNull() }
            ?.takeIf { it.isNotEmpty() }?.also { remote = it } ?: bundled

    /** Einstellungen der aktuellen Gemeinde. */
    val config: TenantConfig get() = slug.let { s -> all.firstOrNull { it.slug == s } ?: bundled.firstOrNull { it.slug == s } ?: bundled.first() }

    /** Dateiordner für Inhalte einer Gemeinde; Westerstede behält den alten Ort. */
    fun folder(base: String, slug: String = this.slug) = if (slug == DEFAULT) base else "$base/tenants/$slug"

    /** Setzt die Gemeinde und verwirft, was nur zur alten passte. */
    fun select(slug: String) {
        val changed = Store.prefs.getString(KEY, null) != slug
        val edit = Store.prefs.edit().putString(KEY, slug)
        if (changed) perTenantKeys.forEach { edit.remove(it) }
        edit.apply()
        chosen = slug
    }

    // MARK: Backend

    private val rows = mutableMapOf<String, Tenant>()

    /** Zeile der aktuellen Gemeinde in `tenants` (ID für alle Abfragen), je Gemeinde einmal geladen. */
    suspend fun current(): Tenant = row(slug)

    suspend fun row(slug: String): Tenant = rows[slug] ?: Backend.supabase.from("tenants").select(Columns.raw("id,slug,name,municipality")) {
        filter { eq("slug", slug) }
    }.decodeSingle<Tenant>().also { rows[slug] = it }

    /** Lädt die Gemeinden der Region neu; ohne Netz bleibt der letzte Stand. */
    suspend fun refresh() {
        runCatching {
            val list = Backend.supabase.from("tenants").select(Columns.raw("id,slug,municipality,config")) {
                filter { eq("region", Brand.current.region) }
                order("municipality", Order.ASCENDING)
            }.decodeList<TenantRow>().mapNotNull { row ->
                val c = runCatching { Http.json.decodeFromJsonElement(TenantRowConfig.serializer(), row.config) }.getOrNull() ?: return@mapNotNull null
                TenantConfig(row.slug, row.municipality, c.center ?: return@mapNotNull null, c.bbox ?: return@mapNotNull null,
                    c.stations.orEmpty(), c.defaultStation.orEmpty(), c.wasteTownId ?: 0, c.busDefaultStop.orEmpty(), row.id,
                    Brand.current.region, c.features, c.ferry, c.tides, c.airStation, c.notes, c.external, c.ris, c.marine)
            }
            if (list.isEmpty()) return
            Store.write("content", "tenants.json", Http.json.encodeToString(listSerializer, list))
            remote = list
        }
    }
}
