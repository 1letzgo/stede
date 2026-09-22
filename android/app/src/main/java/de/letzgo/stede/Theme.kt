package de.letzgo.stede

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** Westerstede-Palette, gleiche Rollen wie StedeTheme in der iOS-App. */
object Stede {
    val deep = Color(0xFF284050)
    val ink = Color(0xFF294753)
    val inkDark = Color(0xFFA9CBD6)
    val red = Color(0xFFD8232F)
    val green = Color(0xFF5C8A12)
    val amber = Color(0xFFE3A11C)
    val teal = Color(0xFF1F7F8C)
    val heather = Color(0xFFC0106E)
    val mudflat = Color(0xFF8A6A3C)
    val sand = Color(0xFFF4F3EC)
    val sandDark = Color(0xFF101A1F)
    val surface = Color(0xFFFFFFFF)
    val surfaceDark = Color(0xFF1B2A32)
}

@Composable
fun StedeTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val scheme = if (dark) darkColorScheme(
        primary = Stede.inkDark, background = Stede.sandDark, surface = Stede.surfaceDark, onSurface = Color(0xFFF2F2F2), secondary = Stede.teal,
    ) else lightColorScheme(
        primary = Stede.ink, background = Stede.sand, surface = Stede.surface, onSurface = Color(0xFF1A1A1A), secondary = Stede.teal,
    )
    MaterialTheme(colorScheme = scheme, content = content)
}
