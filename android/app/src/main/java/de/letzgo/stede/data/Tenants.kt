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
    val stations: List<TenantStation>,
    val defaultStation: String,
    val wasteTownID: Int,
    val busDefaultStop: String,
) {
    val latitude get() = center.getOrElse(0) { 53.2575 }
    val longitude get() = center.getOrElse(1) { 7.9273 }

    fun station(id: String?): TenantStation? =
        stations.firstOrNull { it.id == id } ?: stations.firstOrNull { it.id == defaultStation } ?: stations.firstOrNull()

    /** „Stadt Westerstede“, sonst „Gemeinde …“. */
    val officialName get() = if (slug == Tenants.DEFAULT) "Stadt $municipality" else "Gemeinde $municipality"
}

@Serializable private data class TenantRow(val slug: String, val municipality: String, val config: JsonObject)
@Serializable private data class TenantRowConfig(
    val center: List<Double>? = null, val bbox: List<Double>? = null, val stations: List<TenantStation>? = null,
    @SerialName("default_station") val defaultStation: String? = null,
    @SerialName("waste_town_id") val wasteTownId: Int? = null,
    @SerialName("bus_default_stop") val busDefaultStop: String? = null,
)

/**
 * Welche Gemeinde die App gerade zeigt — wie Tenants in iOS. Die Wahl liegt in den Einstellungen
 * (`tenant.slug`); Stände je Gemeinde liegen in getrennten Ordnern, Westerstede behält die alten.
 */
object Tenants {
    const val DEFAULT = "stede"
    const val KEY = "tenant.slug"
    /** Wird die Gemeinde gewechselt, gelten diese Einstellungen nicht mehr. */
    private val perTenantKeys = listOf("bus.stop", "train.station", "train.direction", "waste.street", "waste.section", "waste.branchSection")
    private val listSerializer = ListSerializer(TenantConfig.serializer())

    /** Gewählte Gemeinde; null, solange beim ersten Start noch keine gewählt ist. Compose beobachtet den Wert. */
    var chosen by mutableStateOf(Store.prefs.getString(KEY, null)); private set

    val slug: String get() = chosen ?: DEFAULT
    val hasChosen get() = chosen != null
    /** Westerstede hat die Daten in den Assets; alle anderen nur aus dem Backend. */
    val usesBundle get() = slug == DEFAULT

    private val bundled: List<TenantConfig> by lazy {
        runCatching { Http.json.decodeFromString(listSerializer, Store.asset("tenants.json")) }.getOrNull()?.takeIf { it.isNotEmpty() }
            ?: listOf(TenantConfig(DEFAULT, "Westerstede", listOf(53.25752, 7.92734), listOf(53.15, 7.78, 53.36, 8.10),
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
            val list = Backend.supabase.from("tenants").select(Columns.raw("slug,municipality,config")) {
                filter { eq("region", "ammerland") }
                order("municipality", Order.ASCENDING)
            }.decodeList<TenantRow>().mapNotNull { row ->
                val c = runCatching { Http.json.decodeFromJsonElement(TenantRowConfig.serializer(), row.config) }.getOrNull() ?: return@mapNotNull null
                TenantConfig(row.slug, row.municipality, c.center ?: return@mapNotNull null, c.bbox ?: return@mapNotNull null,
                    c.stations ?: return@mapNotNull null, c.defaultStation ?: return@mapNotNull null,
                    c.wasteTownId ?: return@mapNotNull null, c.busDefaultStop ?: return@mapNotNull null)
            }
            if (list.isEmpty()) return
            Store.write("content", "tenants.json", Http.json.encodeToString(listSerializer, list))
            remote = list
        }
    }
}
