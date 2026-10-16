package de.letzgo.stede.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import de.letzgo.stede.BuildConfig
import io.ktor.client.plugins.timeout
import io.ktor.client.request.prepareGet
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.contentLength
import io.ktor.utils.io.readAvailable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.security.MessageDigest
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/**
 * Update für APKs außerhalb von Google Play: neue Versionen liegen als Releases im öffentlichen
 * Repo 1letzgo/stede, Tag `<brand>-android-<versionCode>` mit der APK als Asset. Nur der Build-Typ
 * `sideload` (und debug) prüft, lädt die APK in der App und übergibt sie dem Paketinstaller;
 * Play-Builds und Play-Installationen fragen nie (Play aktualisiert selbst).
 */
object AppUpdate {
    private const val RELEASES = "https://api.github.com/repos/1letzgo/stede/releases?per_page=30"
    private const val LAST_CHECK = "update.lastCheck"
    private const val SKIPPED = "update.skipped"

    /** `sha256` aus dem Asset-Digest von GitHub, zum Prüfen des Downloads. */
    data class Release(val versionCode: Int, val name: String, val notes: String, val apkUrl: String, val pageUrl: String, val sha256: String?)

    @Serializable private data class GitRelease(
        @SerialName("tag_name") val tag: String,
        val name: String? = null,
        val body: String? = null,
        val draft: Boolean = false,
        val prerelease: Boolean = false,
        @SerialName("html_url") val htmlUrl: String,
        val assets: List<Asset> = emptyList(),
    )
    @Serializable private data class Asset(val name: String, @SerialName("browser_download_url") val url: String, val digest: String? = null)

    /** Prüft dieser Build überhaupt? Nur `sideload`/debug und nicht aus Google Play installiert. */
    fun isEnabled(context: Context) = BuildConfig.SIDELOAD && !fromPlayStore(context)

    /** Von Google Play installiert? Dann gibt es keine Prüfung. */
    fun fromPlayStore(context: Context): Boolean = runCatching {
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        else @Suppress("DEPRECATION") context.packageManager.getInstallerPackageName(context.packageName)
        installer == "com.android.vending"
    }.getOrDefault(false)

    /** Neueste Version dieser Marke, wenn sie neuer ist als die installierte. */
    suspend fun newer(): Release? {
        val prefix = "${BuildConfig.BRAND}-android-"
        val releases = Http.json.decodeFromString(ListSerializer(GitRelease.serializer()), Http.direct(RELEASES))
        return releases.asSequence()
            .filter { !it.draft && !it.prerelease && it.tag.startsWith(prefix) }
            .mapNotNull { r ->
                val code = r.tag.removePrefix(prefix).toIntOrNull() ?: return@mapNotNull null
                val apk = r.assets.firstOrNull { it.name.endsWith(".apk") } ?: return@mapNotNull null
                Release(code, r.name ?: r.tag, r.body.orEmpty().trim(), apk.url, r.htmlUrl, apk.digest?.removePrefix("sha256:"))
            }
            .maxByOrNull { it.versionCode }
            ?.takeIf { it.versionCode > BuildConfig.VERSION_CODE }
    }

    /** Beim Start höchstens alle sechs Stunden, und nicht für eine Version, die „Später“ bekam. */
    suspend fun checkOnLaunch(context: Context): Release? {
        if (!isEnabled(context)) return null
        val now = System.currentTimeMillis()
        if (now - Store.string(LAST_CHECK, "0").toLong() < 6 * 3600_000L) return null
        val release = runCatching { newer() }.getOrNull()
        Store.setString(LAST_CHECK, "$now")
        return release?.takeIf { it.versionCode > Store.int(SKIPPED) }
    }

    fun skip(release: Release) = Store.setInt(SKIPPED, release.versionCode)

    /** Lädt die APK nach `cache/updates/` und prüft sie gegen den Digest von GitHub. */
    suspend fun download(context: Context, release: Release, progress: (Float?) -> Unit): File = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "updates").apply { mkdirs(); listFiles()?.forEach { it.delete() } }
        val file = File(dir, "${BuildConfig.BRAND}-${release.versionCode}.apk")
        val digest = MessageDigest.getInstance("SHA-256")
        // Mobil kann die APK länger brauchen als die üblichen 30 s.
        Http.client.prepareGet(release.apkUrl) { timeout { requestTimeoutMillis = 10 * 60_000 } }.execute { response ->
            if (response.status.value !in 200..299) error("HTTP ${response.status.value}")
            val total = response.contentLength()
            val channel = response.bodyAsChannel()
            val buffer = ByteArray(64 * 1024)
            var done = 0L
            file.outputStream().use { out ->
                while (true) {
                    val n = channel.readAvailable(buffer, 0, buffer.size)
                    if (n < 0) break
                    if (n == 0) { if (channel.isClosedForRead) break else continue }
                    out.write(buffer, 0, n); digest.update(buffer, 0, n); done += n
                    progress(total?.takeIf { it > 0 }?.let { done.toFloat() / it })
                }
            }
        }
        val hash = digest.digest().joinToString("") { "%02x".format(it) }
        if (release.sha256 != null && !release.sha256.equals(hash, ignoreCase = true)) {
            file.delete(); error("Die heruntergeladene Datei ist beschädigt.")
        }
        file
    }

    /** Darf die App Pakete installieren? Sonst erst die Freigabe in den Android-Einstellungen. */
    fun canInstall(context: Context) = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    fun openInstallPermission(context: Context) = context.startActivity(
        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

    /** Übergibt die APK dem Paketinstaller; Android fragt dann „Installieren?“. */
    fun install(context: Context, file: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.share", file)
        context.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
