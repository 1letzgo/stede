package de.letzgo.stede.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString

/** Ein Ort aus einem Verzeichnis — gleiche Felder wie GastroPlace. */
@Serializable
data class Place(
    val id: String,
    val name: String,
    val category: String,
    val teaser: String? = null,
    val street: String? = null,
    val phone: String? = null,
    val email: String? = null,
    val website: String? = null,
    val hours: String? = null,
    val restDay: String? = null,
    val seasonNote: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val features: List<String> = emptyList(),
    /** Zusätzlicher Link neben der Website, z. B. ein Programm als PDF — nie Bestellplattformen. */
    val extraLinkTitle: String? = null,
    val extraLinkUrl: String? = null,
) {
    /** Liefert nach Hause (laut Lieferando oder Google Maps) — eigene Filter-Pille unter „Gastro“. */
    val delivers get() = DELIVERY in features
    companion object { const val DELIVERY = "Lieferdienst" }
}

@Serializable data class PlaceDirectory(val source: String = "", val fetchedAt: String = "", val places: List<Place> = emptyList())

@Serializable private data class BikeStation(val label: String = "", val street: String = "", val latitude: Double = 0.0, val longitude: Double = 0.0)
@Serializable private data class BikeProvider(val id: String, val name: String, val teaser: String? = null, val phone: String? = null, val email: String? = null, val website: String? = null, val features: List<String> = emptyList(), val stations: List<BikeStation> = emptyList())
@Serializable private data class BikeDirectory(val source: String = "", val fetchedAt: String = "", val providers: List<BikeProvider> = emptyList())

@Serializable private data class PlaceRow(
    @SerialName("external_id") val externalId: String, val directory: String, val kind: String, val name: String,
    val teaser: String? = null, val street: String? = null, val phone: String? = null, val email: String? = null, val website: String? = null,
    val hours: String? = null, @SerialName("rest_day") val restDay: String? = null, @SerialName("season_note") val seasonNote: String? = null,
    val features: List<String> = emptyList(), val lat: Double? = null, val lon: Double? = null, @SerialName("sort_order") val sortOrder: Int = 0,
    @SerialName("extra_link_title") val extraLinkTitle: String? = null, @SerialName("extra_link_url") val extraLinkUrl: String? = null,
)
@Serializable private data class BusStopRow(@SerialName("stop_id") val id: String, val name: String, val lat: Double, val lon: Double)

/** Haltestellen aus `bus_stops` — wenige hundert Zeilen, daher jedes Mal komplett; gespeichert in der Form von `bus-stops.json`. */
private suspend fun syncBusStops(tenantId: String, slug: String) = runCatching {
    val rows = Backend.supabase.from("bus_stops").select(Columns.raw("stop_id,name,lat,lon")) {
        filter { eq("tenant_id", tenantId); exact("deleted_at", null) }
        order("sort_order", io.github.jan.supabase.postgrest.query.Order.ASCENDING); order("name", io.github.jan.supabase.postgrest.query.Order.ASCENDING)
        limit(2000)
    }.decodeList<BusStopRow>()
    if (rows.isNotEmpty()) Store.write(Tenants.folder("content", slug), "bus-stops.json", kotlinx.serialization.json.buildJsonObject {
        put("source", kotlinx.serialization.json.JsonPrimitive("bus_stops"))
        put("stops", kotlinx.serialization.json.buildJsonArray {
            rows.forEach { r -> add(kotlinx.serialization.json.buildJsonObject {
                put("id", kotlinx.serialization.json.JsonPrimitive(r.id)); put("name", kotlinx.serialization.json.JsonPrimitive(r.name))
                put("latitude", kotlinx.serialization.json.JsonPrimitive(r.lat)); put("longitude", kotlinx.serialization.json.JsonPrimitive(r.lon))
            }) }
        })
    }.toString())
}

@Serializable private data class DirectoryRow(val directory: String, val source: String, @SerialName("fetched_at") val fetchedAt: String)

/**
 * Verzeichnisse: Stand aus dem Backend (Dateicache je Gemeinde), sonst — nur für Westerstede — das Bundle
 * aus den Assets. Beim Start zieht [sync] alle Verzeichnisse neu — offline bleibt der letzte Stand.
 */
object Places {
    val assets = mapOf("gastro" to "gastronomie.json", "health" to "gesundheit.json", "leisure" to "freizeit.json", "sights" to "sehenswuerdigkeiten.json", "playgrounds" to "spielplaetze.json", "trips" to "ausfluege.json", "volunteer" to "ehrenamt.json", "bikes" to "fahrradverleih.json")
    private val cache = mutableMapOf<String, PlaceDirectory>()

    /** Je Gemeinde einmal gelesen; der Schlüssel enthält die Gemeinde, ein Wechsel liest neu. */
    fun directory(key: String): PlaceDirectory = cache.getOrPut("${Tenants.slug}/$key") {
        Store.read(Tenants.folder("content"), "$key.json")?.let { runCatching { Http.json.decodeFromString<PlaceDirectory>(it) }.getOrNull() }?.takeIf { it.places.isNotEmpty() }
            ?: if (Tenants.usesBundle) bundled(key) else PlaceDirectory()
    }

    private fun bundled(key: String): PlaceDirectory {
        val text = Store.asset(assets.getValue(key))
        if (key != "bikes") return Http.json.decodeFromString(text)
        val bikes = Http.json.decodeFromString<BikeDirectory>(text)
        return PlaceDirectory(bikes.source, bikes.fetchedAt, bikes.providers.map { p ->
            val st = p.stations.firstOrNull()
            Place(p.id, p.name, "Fahrrad", p.teaser, st?.street, p.phone, p.email, p.website, latitude = st?.latitude, longitude = st?.longitude, features = p.features)
        })
    }

    /** Ohne Angabe die aktuelle Gemeinde; beim Wechsel die neue, bevor sie gilt. */
    suspend fun sync(slug: String = Tenants.slug) {
        runCatching {
            val tenant = Tenants.row(slug)
            val metas = Backend.supabase.from("place_directories").select(Columns.raw("directory,source,fetched_at")) { filter { eq("tenant_id", tenant.id) } }.decodeList<DirectoryRow>()
            for (meta in metas) {
                if (meta.directory !in assets) continue
                val rows = Backend.supabase.from("places").select(Columns.raw("external_id,directory,kind,name,teaser,street,phone,email,website,hours,rest_day,season_note,features,lat,lon,sort_order,extra_link_title,extra_link_url")) {
                    filter { eq("tenant_id", tenant.id); eq("directory", meta.directory); exact("deleted_at", null) }
                    order("sort_order", io.github.jan.supabase.postgrest.query.Order.ASCENDING)
                }.decodeList<PlaceRow>()
                if (rows.isEmpty()) continue
                val dir = PlaceDirectory(meta.source, meta.fetchedAt, rows.map {
                    Place(it.externalId, it.name, it.kind, it.teaser, it.street, it.phone, it.email, it.website, it.hours, it.restDay, it.seasonNote, it.lat, it.lon, it.features, it.extraLinkTitle, it.extraLinkUrl)
                })
                Store.write(Tenants.folder("content", slug), "${meta.directory}.json", Http.json.encodeToString(dir))
                cache["$slug/${meta.directory}"] = dir
            }
            syncBusStops(tenant.id, slug)
        }
    }
}
