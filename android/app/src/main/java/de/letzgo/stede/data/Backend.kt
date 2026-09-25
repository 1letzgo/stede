package de.letzgo.stede.data

import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsBytes
import io.ktor.client.statement.bodyAsText
import kotlinx.serialization.json.Json

/** Gemeinsames Supabase-Projekt „lokalz“ — dieselben Tabellen wie die iOS-App. */
object Backend {
    const val URL = "https://fkzjlecsetbnumtqrnem.supabase.co"
    const val KEY = "sb_publishable_5ptJm36r8qnhKrGoGOWd0A_5uOpaBmH"
    const val TENANT = "stede"

    val supabase = createSupabaseClient(URL, KEY) {
        install(Auth) { scheme = "stede"; host = "auth-callback" }
        install(Postgrest)
        install(Storage)
        install(Functions)
    }

    fun logoUrl(path: String?) = path?.let { "$URL/storage/v1/object/public/community-logos/$it" }
    fun avatarUrl(path: String?) = path?.takeIf { it.isNotBlank() }?.let { if (it.startsWith("http")) it else "$URL/storage/v1/object/public/avatars/$it" }
    fun photoUrl(path: String?) = path?.let { "$URL/storage/v1/object/public/event-photos/$it" }
    fun feedUrl(token: String, scope: String = "mine") = "$URL/functions/v1/calendar-feed/$token.ics?scope=$scope"
    fun webcalUrl(token: String, scope: String = "mine") = feedUrl(token, scope).replace("https://", "webcal://")
}

/** HTTP für die öffentlichen Quellen (Bahn, Bus, Wetter, Luft, Abfuhr) — Safari-Kennung wie iOS. */
object Http {
    val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }
    val client = HttpClient(OkHttp) { install(HttpTimeout) { requestTimeoutMillis = 30_000 } }
    private const val UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /** Live-Dienste laufen zuerst über den Server-Zwischenspeicher (Edge Function `upstream`), sonst direkt — wie iOS. */
    private val proxied = setOf("api.brightsky.dev", "luftdaten.umweltbundesamt.de", "dbf.finalrewind.org", "fahrplaner.vbn.de")
    private fun proxyUrl(url: String): String? {
        val host = runCatching { java.net.URI(url).host }.getOrNull() ?: return null
        return if (host in proxied) "${Backend.URL}/functions/v1/upstream?url=${java.net.URLEncoder.encode(url, "UTF-8")}" else null
    }

    suspend fun text(url: String): String = proxyUrl(url)?.let { p -> runCatching { ok(p).bodyAsText() }.getOrNull() } ?: direct(url)
    suspend fun bytes(url: String): ByteArray = proxyUrl(url)?.let { p -> runCatching { ok(p).bodyAsBytes() }.getOrNull() } ?: ok(url).bodyAsBytes()
    suspend fun direct(url: String): String = ok(url).bodyAsText()

    private suspend fun ok(url: String) = client.get(url) { header("User-Agent", UA) }.also {
        if (it.status.value !in 200..299) error("HTTP ${it.status.value}")
    }
}
