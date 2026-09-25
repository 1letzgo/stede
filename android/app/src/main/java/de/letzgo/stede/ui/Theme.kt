package de.letzgo.stede.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color

/** Palette im Rot des App-Icons, mit denselben Rollen wie StedeTheme in iOS; hell und dunkel. */
object C {
    val deep = Color(0xFF7A0000) // gefüllte Chips: Rot des App-Icons
    val bar = Color(0xFF7A0000) // Leiste: Rot aus dem App-Icon
    val red @Composable @ReadOnlyComposable get() = pick(0xFFD8232F, 0xFFF0566A)
    val green @Composable @ReadOnlyComposable get() = pick(0xFF5C8A12, 0xFF96CD20)
    val amber @Composable @ReadOnlyComposable get() = pick(0xFFE3A11C, 0xFFFAB325)
    val teal @Composable @ReadOnlyComposable get() = pick(0xFF963737, 0xFFE39A9A)
    val heather @Composable @ReadOnlyComposable get() = pick(0xFFC0106E, 0xFFE85CA6)
    val mudflat @Composable @ReadOnlyComposable get() = pick(0xFF8A6A3C, 0xFFD0B48A)
    val ink @Composable @ReadOnlyComposable get() = pick(0xFF7A0000, 0xFFF0B8B8)
    val sand @Composable @ReadOnlyComposable get() = pick(0xFFF6F1EE, 0xFF171111)
    val surface @Composable @ReadOnlyComposable get() = pick(0xFFFFFFFF, 0xFF261C1C)
    val text @Composable @ReadOnlyComposable get() = pick(0xFF1A1A1A, 0xFFF2F2F2)
    val secondary @Composable @ReadOnlyComposable get() = text.copy(alpha = 0.62f)
    val tertiary @Composable @ReadOnlyComposable get() = text.copy(alpha = 0.38f)

    @Composable @ReadOnlyComposable
    private fun pick(light: Long, dark: Long) = Color(if (isSystemInDarkTheme()) dark else light)
}

@Composable
fun StedeTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = Color(0xFFE39A9A), background = Color(0xFF171111), surface = Color(0xFF261C1C), onSurface = Color(0xFFF2F2F2), onBackground = Color(0xFFF2F2F2), surfaceContainer = Color(0xFF261C1C))
    else lightColorScheme(primary = Color(0xFF7A0000), background = Color(0xFFF6F1EE), surface = Color.White, onSurface = Color(0xFF1A1A1A), onBackground = Color(0xFF1A1A1A), surfaceContainer = Color.White)
    MaterialTheme(colorScheme = scheme, content = content)
}
