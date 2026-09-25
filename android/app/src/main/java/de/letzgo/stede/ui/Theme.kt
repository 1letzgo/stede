package de.letzgo.stede.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color

/** Westerstede-Palette nach westerstede.de (Logo, Website) — dieselben Rollen wie StedeTheme in iOS; hell und dunkel. */
object C {
    val deep = Color(0xFF294753) // Logo-Petrol: gefüllte Chips
    val bar @Composable @ReadOnlyComposable get() = pick(0xFF294753, 0xFF1F3640) // Leiste
    val red @Composable @ReadOnlyComposable get() = pick(0xFFE30613, 0xFFFF5A64) // Rhododendron-Rot aus dem Logo
    val green @Composable @ReadOnlyComposable get() = pick(0xFF37AB49, 0xFF6FD17F) // Stadtgrün
    val amber @Composable @ReadOnlyComposable get() = pick(0xFFFF8A00, 0xFFFFA53D) // Orange der Website
    val teal @Composable @ReadOnlyComposable get() = pick(0xFF2E6EA5, 0xFF7FB1DE) // Seitenblau als Akzent
    val heather @Composable @ReadOnlyComposable get() = pick(0xFFC0106E, 0xFFE85CA6)
    val mudflat @Composable @ReadOnlyComposable get() = pick(0xFF8A6A3C, 0xFFD0B48A)
    val ink @Composable @ReadOnlyComposable get() = pick(0xFF294753, 0xFF9FC3D0)
    val sand @Composable @ReadOnlyComposable get() = pick(0xFFF1EFEE, 0xFF121719) // warmes Grau der Website
    val surface @Composable @ReadOnlyComposable get() = pick(0xFFFFFFFF, 0xFF1E2528)
    val text @Composable @ReadOnlyComposable get() = pick(0xFF1A1A1A, 0xFFF2F2F2)
    val secondary @Composable @ReadOnlyComposable get() = text.copy(alpha = 0.62f)
    val tertiary @Composable @ReadOnlyComposable get() = text.copy(alpha = 0.38f)

    @Composable @ReadOnlyComposable
    private fun pick(light: Long, dark: Long) = Color(if (isSystemInDarkTheme()) dark else light)
}

@Composable
fun StedeTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = Color(0xFF9FC3D0), background = Color(0xFF121719), surface = Color(0xFF1E2528), onSurface = Color(0xFFF2F2F2), onBackground = Color(0xFFF2F2F2), surfaceContainer = Color(0xFF1E2528))
    else lightColorScheme(primary = Color(0xFF294753), background = Color(0xFFF1EFEE), surface = Color.White, onSurface = Color(0xFF1A1A1A), onBackground = Color(0xFF1A1A1A), surfaceContainer = Color.White)
    MaterialTheme(colorScheme = scheme, content = content)
}
