package de.letzgo.stede.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import de.letzgo.stede.data.Brand

/** Farbe hell/dunkel als ARGB. */
data class Tone(val light: Long, val dark: Long)

/**
 * Palette einer Marke — dieselben Rollen wie die iOS-Colorsets `<Präfix>{Sand,Surface,Harbor,Dune,Sun,Sea,
 * Deep,Bar,Ink,Heather,Mudflat}`. Neue Marken (Skill `new-region-app`) fügen hier einen Eintrag hinzu.
 */
data class Palette(
    val sand: Tone, val surface: Tone, val harbor: Tone, val dune: Tone, val sun: Tone, val sea: Tone,
    val deep: Tone, val bar: Tone, val ink: Tone, val heather: Tone, val mudflat: Tone,
) {
    companion object {
        // brands: start
        /** stede: Westerstede nach westerstede.de (Logo-Petrol, Rhododendron-Rot, Stadtgrün). */
        val stede = Palette(
            sand = Tone(0xFFF1EFEE, 0xFF121719), surface = Tone(0xFFFFFFFF, 0xFF1E2528), harbor = Tone(0xFFE30613, 0xFFFF5A64),
            dune = Tone(0xFF37AB49, 0xFF6FD17F), sun = Tone(0xFFFF8A00, 0xFFFFA53D), sea = Tone(0xFF2E6EA5, 0xFF7FB1DE),
            deep = Tone(0xFF294753, 0xFF294753), bar = Tone(0xFF294753, 0xFF1F3640), ink = Tone(0xFF294753, 0xFF9FC3D0),
            heather = Tone(0xFFC0106E, 0xFFE85CA6), mudflat = Tone(0xFF8A6A3C, 0xFFD0B48A),
        )
        /** loog: Insel-Palette (Colorsets `Loog*`). */
        val loog = Palette(
            sand = Tone(0xFFF7F1E5, 0xFF101826), surface = Tone(0xFFFFFFFF, 0xFF1C2740), harbor = Tone(0xFFC4453B, 0xFFE88074),
            dune = Tone(0xFF3E7C4F, 0xFF7FC08F), sun = Tone(0xFFD98E2B, 0xFFF2B95C), sea = Tone(0xFF1F7A8C, 0xFF6FC3D6),
            deep = Tone(0xFF1B4182, 0xFF233D66), bar = Tone(0xFF1B4182, 0xFF233D66), ink = Tone(0xFF1B4182, 0xFFCCE0F5),
            heather = Tone(0xFF8B579C, 0xFFCAA3DB), mudflat = Tone(0xFF8B6B4B, 0xFFD5B793),
        )
        val all = mapOf("stede" to stede, "loog" to loog)
        // brands: end

        val current: Palette = all[Brand.current.id] ?: stede
    }
}

/** Farben der laufenden Marke — dieselben Rollen wie StedeTheme in iOS, hell und dunkel. */
object C {
    private val p = Palette.current
    val deep = Color(p.deep.light) // gefüllte Chips, in beiden Modi dunkel
    val bar @Composable @ReadOnlyComposable get() = pick(p.bar) // Leiste
    val red @Composable @ReadOnlyComposable get() = pick(p.harbor)
    val green @Composable @ReadOnlyComposable get() = pick(p.dune)
    val amber @Composable @ReadOnlyComposable get() = pick(p.sun)
    val teal @Composable @ReadOnlyComposable get() = pick(p.sea) // Akzent
    val heather @Composable @ReadOnlyComposable get() = pick(p.heather)
    val mudflat @Composable @ReadOnlyComposable get() = pick(p.mudflat)
    val ink @Composable @ReadOnlyComposable get() = pick(p.ink)
    val sand @Composable @ReadOnlyComposable get() = pick(p.sand)
    val surface @Composable @ReadOnlyComposable get() = pick(p.surface)
    val text @Composable @ReadOnlyComposable get() = Color(if (isSystemInDarkTheme()) 0xFFF2F2F2 else 0xFF1A1A1A)
    val secondary @Composable @ReadOnlyComposable get() = text.copy(alpha = 0.62f)
    val tertiary @Composable @ReadOnlyComposable get() = text.copy(alpha = 0.38f)

    @Composable @ReadOnlyComposable
    private fun pick(t: Tone) = Color(if (isSystemInDarkTheme()) t.dark else t.light)
}

@Composable
fun StedeTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = C.ink, background = C.sand, surface = C.surface, onSurface = Color(0xFFF2F2F2), onBackground = Color(0xFFF2F2F2), surfaceContainer = C.surface)
    else lightColorScheme(primary = C.ink, background = C.sand, surface = Color.White, onSurface = Color(0xFF1A1A1A), onBackground = Color(0xFF1A1A1A), surfaceContainer = Color.White)
    MaterialTheme(colorScheme = scheme, content = content)
}
