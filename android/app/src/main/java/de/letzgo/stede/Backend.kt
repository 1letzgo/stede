package de.letzgo.stede

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Zugang zum gemeinsamen Supabase-Projekt — gleiche Tabellen wie die iOS-App. */
object Backend {
    const val url = "https://fkzjlecsetbnumtqrnem.supabase.co"
    const val key = "sb_publishable_5ptJm36r8qnhKrGoGOWd0A_5uOpaBmH"
    const val tenantSlug = "stede"

    val json = Json { ignoreUnknownKeys = true; isLenient = true }
    val client = HttpClient(OkHttp) { install(ContentNegotiation) { json(json) } }

    private suspend inline fun <reified T> rest(path: String, vararg params: Pair<String, String>): T =
        client.get("$url/rest/v1/$path") {
            header("apikey", key)
            header("Authorization", "Bearer $key")
            params.forEach { parameter(it.first, it.second) }
        }.body()

    suspend fun tenant(): Tenant =
        rest<List<Tenant>>("tenants", "select" to "id,slug,name,municipality", "slug" to "eq.$tenantSlug").first()

    suspend fun cityEvents(tenantId: String, from: String, to: String): List<CityEvent> =
        rest("city_events", "select" to "external_id,title,day,starts_at,ends_at,summary,location,organizer,category,series_note,detail_url",
            "tenant_id" to "eq.$tenantId", "day" to "gte.$from", "and" to "(day.lt.$to,deleted_at.is.null)", "order" to "starts_at")

    suspend fun publicEvents(tenantId: String, fromIso: String, toIso: String): List<PublicEvent> =
        rest("v_public_events", "select" to "id,community_name,community_logo_path,title,description,starts_at,ends_at,location,image_path,helpers_needed",
            "tenant_id" to "eq.$tenantId", "starts_at" to "gte.$fromIso", "and" to "(starts_at.lt.$toIso)", "order" to "starts_at")

    suspend fun communities(tenantId: String): List<Community> =
        rest("v_community_overview", "select" to "id,name,description,visibility,join_policy,status,logo_path,member_count",
            "tenant_id" to "eq.$tenantId", "status" to "eq.approved", "visibility" to "eq.listed", "order" to "name")

    suspend fun places(tenantId: String, directory: String): List<Place> =
        rest("places", "select" to "external_id,directory,kind,name,teaser,street,phone,website,hours,season_note,lat,lon,sort_order",
            "tenant_id" to "eq.$tenantId", "directory" to "eq.$directory", "deleted_at" to "is.null", "order" to "sort_order")

    fun logoUrl(path: String?) = path?.let { "$url/storage/v1/object/public/community-logos/$it" }
    fun photoUrl(path: String?) = path?.let { "$url/storage/v1/object/public/event-photos/$it" }
}

@Serializable data class Tenant(val id: String, val slug: String, val name: String, val municipality: String)

@Serializable data class CityEvent(
    @SerialName("external_id") val externalId: String, val title: String, val day: String,
    @SerialName("starts_at") val startsAt: String? = null, @SerialName("ends_at") val endsAt: String? = null,
    val summary: String = "", val location: String? = null, val organizer: String? = null, val category: String? = null,
    @SerialName("series_note") val seriesNote: String? = null, @SerialName("detail_url") val detailUrl: String? = null,
)

@Serializable data class PublicEvent(
    val id: String, @SerialName("community_name") val communityName: String, @SerialName("community_logo_path") val communityLogoPath: String? = null,
    val title: String, val description: String = "", @SerialName("starts_at") val startsAt: String, @SerialName("ends_at") val endsAt: String? = null,
    val location: String? = null, @SerialName("image_path") val imagePath: String? = null, @SerialName("helpers_needed") val helpersNeeded: Int = 0,
)

@Serializable data class Community(
    val id: String, val name: String, val description: String = "", val visibility: String, @SerialName("join_policy") val joinPolicy: String,
    val status: String, @SerialName("logo_path") val logoPath: String? = null, @SerialName("member_count") val memberCount: Int = 0,
)

@Serializable data class Place(
    @SerialName("external_id") val id: String, val directory: String, val kind: String, val name: String, val teaser: String? = null,
    val street: String? = null, val phone: String? = null, val website: String? = null, val hours: String? = null,
    @SerialName("season_note") val seasonNote: String? = null, val lat: Double? = null, val lon: Double? = null, @SerialName("sort_order") val sortOrder: Int = 0,
)
