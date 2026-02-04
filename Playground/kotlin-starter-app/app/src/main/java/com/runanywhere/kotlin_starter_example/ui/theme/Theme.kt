package com.runanywhere.kotlin_starter_example.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Color palette matching Flutter app
val PrimaryDark = Color(0xFF0A0E1A)
val PrimaryMid = Color(0xFF1A1F35)
val SurfaceCard = Color(0xFF1E2536)
val AccentCyan = Color(0xFF06B6D4)
val AccentViolet = Color(0xFF8B5CF6)
val AccentPink = Color(0xFFEC4899)
val AccentGreen = Color(0xFF10B981)
val TextPrimary = Color(0xFFFFFFFF)
val TextMuted = Color(0xFF94A3B8)

private val DarkColorScheme = darkColorScheme(
    primary = AccentCyan,
    secondary = AccentViolet,
    tertiary = AccentPink,
    background = PrimaryDark,
    surface = SurfaceCard,
    onPrimary = Color.White,
    onSecondary = Color.White,
    onTertiary = Color.White,
    onBackground = TextPrimary,
    onSurface = TextPrimary,
)

@Composable
fun KotlinStarterTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = Typography,
        content = content
    )
}
