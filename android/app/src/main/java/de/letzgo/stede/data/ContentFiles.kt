package de.letzgo.stede.data

import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer

@Serializable private data class ContentFileRow(val name: String, val path: String, @SerialName("updated_at") val updatedAt: String)

/**
 * Statische Inhalte als Dateien im öffentlichen Bucket `content` (Tabelle `content_files`) — wie ContentFiles in iOS:
 * Bushaltestellen, Straßenliste der Abfuhr, Offline-Karte. Beim Start nur Geändertes laden; Leser nehmen den
 * lokalen Stand der aktuellen Gemeinde, sonst (nur Westerstede) das Asset. Ein neuer Stand gilt ab dem nächsten
 * Start oder Gemeindewechsel.
 */
object ContentFiles {
    private const val FOLDER = "content-files"
    private val manifestSerializer = MapSerializer(String.serializer(), String.serializer())

    /** Lokal geladener Stand der aktuellen Gemeinde, sonst null (dann gilt das Asset). */
    fun text(name: String): String? = Store.read(Tenants.folder(FOLDER), "$name.json")

    /** Ohne Angabe die aktuelle Gemeinde; beim Wechsel die neue, bevor sie gilt. */
    suspend fun sync(slug: String = Tenants.slug) {
        runCatching {
            val folder = Tenants.folder(FOLDER, slug)
            val tenant = Tenants.row(slug)
            val rows = Backend.supabase.from("content_files").select(Columns.raw("name,path,updated_at")) { filter { eq("tenant_id", tenant.id) } }.decodeList<ContentFileRow>()
            val manifest = (Store.read(folder, "manifest.json")?.let { runCatching { Http.json.decodeFromString(manifestSerializer, it) }.getOrNull() } ?: emptyMap()).toMutableMap()
            for (row in rows) {
                if (manifest[row.name] == row.updatedAt && Store.read(folder, "${row.name}.json") != null) continue
                // CDN-Cache (1 h) umgehen: sonst käme nach einem Update die alte Datei, und weil `updated_at` dann stimmt,
                // würde nie neu geladen.
                val version = java.net.URLEncoder.encode(row.updatedAt, "UTF-8")
                val body = runCatching { Http.direct("${Backend.URL}/storage/v1/object/public/content/${row.path}?v=$version") }.getOrNull() ?: continue
                if (runCatching { Http.json.parseToJsonElement(body) }.isFailure) continue
                Store.write(folder, "${row.name}.json", body)
                manifest[row.name] = row.updatedAt
            }
            Store.write(folder, "manifest.json", Http.json.encodeToString(manifestSerializer, manifest))
        }
    }
}
