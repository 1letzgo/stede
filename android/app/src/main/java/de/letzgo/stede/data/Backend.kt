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
    fun photoUrl(path: String?) = path?.let { "$URL/storage/v1/object/public/event-photos/$it" }
    fun feedUrl(token: String, scope: String = "mine") = "$URL/functions/v1/calendar-feed/$token.ics?scope=$scope"
    fun webcalUrl(token: String, scope: String = "mine") = feedUrl(token, scope).replace("https://", "webcal://")
}

/** HTTP für die öffentlichen Quellen (Bahn, Bus, Wetter, Luft, Abfuhr) — Safari-Kennung wie iOS. */
object Http {
    val json = Json { ignoreUnknownKeys = true; isLenient = true; coerceInputValues = true }
    val client = HttpClient(OkHttp) { install(HttpTimeout) { requestTimeoutMillis = 30_000 } }
    private const val UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    suspend fun text(url: String): String = client.get(url) { header("User-Agent", UA) }.bodyAsText()
    suspend fun bytes(url: String): ByteArray = client.get(url) { header("User-Agent", UA) }.bodyAsBytes()
}
