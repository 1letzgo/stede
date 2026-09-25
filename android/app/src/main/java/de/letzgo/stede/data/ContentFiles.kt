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
 * lokalen Stand, sonst das Asset. Ein neuer Stand gilt ab dem nächsten Start.
 */
object ContentFiles {
    private const val FOLDER = "content-files"
    private val manifestSerializer = MapSerializer(String.serializer(), String.serializer())

    /** Lokal geladener Stand, sonst null (dann gilt das Asset). */
    fun text(name: String): String? = Store.read(FOLDER, "$name.json")

    suspend fun sync() {
        runCatching {
            val tenant = Tenants.current()
            val rows = Backend.supabase.from("content_files").select(Columns.raw("name,path,updated_at")) { filter { eq("tenant_id", tenant.id) } }.decodeList<ContentFileRow>()
            val manifest = (Store.read(FOLDER, "manifest.json")?.let { runCatching { Http.json.decodeFromString(manifestSerializer, it) }.getOrNull() } ?: emptyMap()).toMutableMap()
            for (row in rows) {
                if (manifest[row.name] == row.updatedAt && text(row.name) != null) continue
                val body = runCatching { Http.direct("${Backend.URL}/storage/v1/object/public/content/${row.path}") }.getOrNull() ?: continue
                if (runCatching { Http.json.parseToJsonElement(body) }.isFailure) continue
                Store.write(FOLDER, "${row.name}.json", body)
                manifest[row.name] = row.updatedAt
            }
            Store.write(FOLDER, "manifest.json", Http.json.encodeToString(manifestSerializer, manifest))
        }
    }
}
