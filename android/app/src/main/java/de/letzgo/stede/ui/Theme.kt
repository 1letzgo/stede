package de.letzgo.stede.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import de.letzgo.stede.data.Brand

/**
 * Palette der Marke — dieselben Rollen wie StedeTheme in iOS, hell und dunkel. stede: Westerstede nach
 * westerstede.de (Logo, Website); loog: Insel-Palette (Colorsets `Loog*`).
 */
object C {
    private val loog = Brand.current.id == "loog"
    val deep = Color(if (loog) 0xFF1B4182 else 0xFF294753) // gefüllte Chips
    val bar @Composable @ReadOnlyComposable get() = if (loog) pick(0xFF1B4182, 0xFF233D66) else pick(0xFF294753, 0xFF1F3640) // Leiste
    val red @Composable @ReadOnlyComposable get() = if (loog) pick(0xFFC4453B, 0xFFE88074) else pick(0xFFE30613, 0xFFFF5A64) // Hafenrot / Rhododendron-Rot
    val green @Composable @ReadOnlyComposable get() = if (loog) pick(0xFF3E7C4F, 0xFF7FC08F) else pick(0xFF37AB49, 0xFF6FD17F) // Düne / Stadtgrün
    val amber @Composable @ReadOnlyComposable get() = if (loog) pick(0xFFD98E2B, 0xFFF2B95C) else pick(0xFFFF8A00, 0xFFFFA53D) // Sonne / Orange
    val teal @Composable @ReadOnlyComposable get() = if (loog) pick(0xFF1F7A8C, 0xFF6FC3D6) else pick(0xFF2E6EA5, 0xFF7FB1DE) // Meer / Seitenblau
    val heather @Composable @ReadOnlyComposable get() = if (loog) pick(0xFF8B579C, 0xFFCAA3DB) else pick(0xFFC0106E, 0xFFE85CA6)
    val mudflat @Composable @ReadOnlyComposable get() = if (loog) pick(0xFF8B6B4B, 0xFFD5B793) else pick(0xFF8A6A3C, 0xFFD0B48A)
    val ink @Composable @ReadOnlyComposable get() = if (loog) pick(0xFF1B4182, 0xFFCCE0F5) else pick(0xFF294753, 0xFF9FC3D0)
    val sand @Composable @ReadOnlyComposable get() = if (loog) pick(0xFFF7F1E5, 0xFF101826) else pick(0xFFF1EFEE, 0xFF121719)
    val surface @Composable @ReadOnlyComposable get() = if (loog) pick(0xFFFFFFFF, 0xFF1C2740) else pick(0xFFFFFFFF, 0xFF1E2528)
    val text @Composable @ReadOnlyComposable get() = pick(0xFF1A1A1A, 0xFFF2F2F2)
    val secondary @Composable @ReadOnlyComposable get() = text.copy(alpha = 0.62f)
    val tertiary @Composable @ReadOnlyComposable get() = text.copy(alpha = 0.38f)

    @Composable @ReadOnlyComposable
    private fun pick(light: Long, dark: Long) = Color(if (isSystemInDarkTheme()) dark else light)
}

@Composable
fun StedeTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = C.ink, background = C.sand, surface = C.surface, onSurface = Color(0xFFF2F2F2), onBackground = Color(0xFFF2F2F2), surfaceContainer = C.surface)
    else lightColorScheme(primary = C.ink, background = C.sand, surface = Color.White, onSurface = Color(0xFF1A1A1A), onBackground = Color(0xFF1A1A1A), surfaceContainer = Color.White)
    MaterialTheme(colorScheme = scheme, content = content)
}
