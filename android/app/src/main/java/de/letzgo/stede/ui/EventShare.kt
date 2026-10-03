package de.letzgo.stede.ui

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import de.letzgo.stede.data.Brand
import de.letzgo.stede.data.EventInfo
import de.letzgo.stede.data.Http
import de.letzgo.stede.data.Town
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Teilen wie in „SPD vor Ort“ (EventShare in iOS): Terminbild plus fertiger Text, ohne Bild nur der Text. */
object EventShare {
    fun text(e: EventInfo): String {
        val start = e.starts.withZoneSameInstant(Town.zone)
        val end = e.ends?.withZoneSameInstant(Town.zone)
        var wann = "${start.format(Town.fmt("EEEE, dd.MM.yyyy"))}, ${start.format(Town.hm)}"
        if (end != null && end.toLocalDate() == start.toLocalDate() && end.isAfter(start)) wann += "–${end.format(Town.hm)}"
        val parts = mutableListOf(e.title, "Wann: $wann Uhr")
        e.location?.takeIf { it.isNotBlank() }?.let { parts += "Ort: $it" }
        val desc = e.description.trim()
        if (desc.isNotEmpty()) parts += if (desc.length > 450) desc.take(450) + "…" else desc
        parts += "${e.community} · geteilt aus der ${Brand.current.displayName}-App"
        return parts.joinToString("\n\n")
    }

    /** Öffnet das System-Teilen-Menü; das Bild wird dafür kurz im Cache abgelegt. */
    suspend fun share(context: Context, e: EventInfo) {
        val text = text(e)
        val intent = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_SUBJECT, e.title).putExtra(Intent.EXTRA_TEXT, text)
        val file = e.imageUrl?.let { url ->
            runCatching {
                withContext(Dispatchers.IO) {
                    File(context.cacheDir, "shared").apply { mkdirs() }.resolve("termin.jpg").apply { writeBytes(Http.bytes(url)) }
                }
            }.getOrNull()
        }
        if (file != null) {
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.share", file)
            intent.setType("image/jpeg").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } else intent.setType("text/plain")
        context.startActivity(Intent.createChooser(intent, "Termin teilen"))
    }
}
