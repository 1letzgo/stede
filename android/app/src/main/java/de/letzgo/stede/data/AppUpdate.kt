package de.letzgo.stede.data

import android.content.Context
import android.os.Build
import de.letzgo.stede.BuildConfig
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/**
 * Update-Prüfung für APKs außerhalb von Google Play: neue Versionen liegen als Releases im
 * öffentlichen Repo 1letzgo/stede, Tag `<brand>-android-<versionCode>` mit der APK als Asset.
 * Play-Installationen fragen nie nach (Play aktualisiert selbst, Selbst-Updates sind dort verboten).
 */
object AppUpdate {
    private const val RELEASES = "https://api.github.com/repos/1letzgo/stede/releases?per_page=30"
    private const val LAST_CHECK = "update.lastCheck"
    private const val SKIPPED = "update.skipped"

    data class Release(val versionCode: Int, val name: String, val notes: String, val apkUrl: String, val pageUrl: String)

    @Serializable private data class GitRelease(
        @SerialName("tag_name") val tag: String,
        val name: String? = null,
        val body: String? = null,
        val draft: Boolean = false,
        val prerelease: Boolean = false,
        @SerialName("html_url") val htmlUrl: String,
        val assets: List<Asset> = emptyList(),
    )
    @Serializable private data class Asset(val name: String, @SerialName("browser_download_url") val url: String)

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
                Release(code, r.name ?: r.tag, r.body.orEmpty().trim(), apk.url, r.htmlUrl)
            }
            .maxByOrNull { it.versionCode }
            ?.takeIf { it.versionCode > BuildConfig.VERSION_CODE }
    }

    /** Beim Start höchstens alle sechs Stunden, und nicht für eine Version, die „Später“ bekam. */
    suspend fun checkOnLaunch(context: Context): Release? {
        if (fromPlayStore(context)) return null
        val now = System.currentTimeMillis()
        if (now - Store.string(LAST_CHECK, "0").toLong() < 6 * 3600_000L) return null
        val release = runCatching { newer() }.getOrNull()
        Store.setString(LAST_CHECK, "$now")
        return release?.takeIf { it.versionCode > Store.int(SKIPPED) }
    }

    fun skip(release: Release) = Store.setInt(SKIPPED, release.versionCode)
}
