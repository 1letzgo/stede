package de.letzgo.stede.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.time.LocalDate

@Serializable data class CityEvent(
    @SerialName("external_id") val externalId: String, val title: String, val day: String,
    @SerialName("starts_at") val startsAt: String? = null, @SerialName("ends_at") val endsAt: String? = null,
    val summary: String = "", val location: String? = null, val organizer: String? = null, val category: String? = null,
    @SerialName("series_note") val seriesNote: String? = null, @SerialName("detail_url") val detailUrl: String? = null,
)

/** Stadt-Termine je Woche aus `city_events`, offline aus dem Dateicache. */
object CityEvents {
    fun cached(weekStart: LocalDate): List<CityEvent>? = Store.read("events", "$weekStart.json")?.let { runCatching { Http.json.decodeFromString(ListSerializer(CityEvent.serializer()), it) }.getOrNull() }

    suspend fun week(weekStart: LocalDate): List<CityEvent> {
        val tenant = Tenants.current()
        val rows = Backend.supabase.from("city_events").select(Columns.raw("external_id,title,day,starts_at,ends_at,summary,location,organizer,category,series_note,detail_url")) {
            filter { eq("tenant_id", tenant.id); gte("day", weekStart.toString()); lt("day", weekStart.plusDays(7).toString()); exact("deleted_at", null) }
            order("starts_at", Order.ASCENDING)
        }.decodeList<CityEvent>()
        Store.write("events", "$weekStart.json", Http.json.encodeToString(ListSerializer(CityEvent.serializer()), rows))
        return rows
    }
}
