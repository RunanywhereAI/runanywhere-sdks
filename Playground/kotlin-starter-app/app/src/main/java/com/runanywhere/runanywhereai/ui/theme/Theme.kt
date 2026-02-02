package com.runanywhere.runanywhereai.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

/**
 * Light Color Scheme - RunAnywhere Brand Theme
 * Modern color scheme matching RunAnywhere.ai website
 */
private val LightColorScheme =
    lightColorScheme(
        // Primary colors
        primary = AppColors.primaryAccent,
        onPrimary = Color.White,
        primaryContainer = AppColors.primaryAccent.copy(alpha = 0.1f),
        onPrimaryContainer = AppColors.primaryAccent,
        // Secondary colors
        secondary = AppColors.primaryPurple,
        onSecondary = Color.White,
        secondaryContainer = AppColors.primaryPurple.copy(alpha = 0.1f),
        onSecondaryContainer = AppColors.primaryPurple,
        // Tertiary colors
        tertiary = AppColors.primaryGreen,
        onTertiary = Color.White,
        tertiaryContainer = AppColors.primaryGreen.copy(alpha = 0.1f),
        onTertiaryContainer = AppColors.primaryGreen,
        // Background colors
        background = AppColors.backgroundGrouped,
        onBackground = AppColors.textPrimary,
        // Surface colors
        surface = AppColors.backgroundPrimary,
        onSurface = AppColors.textPrimary,
        surfaceVariant = AppColors.backgroundSecondary,
        onSurfaceVariant = AppColors.textSecondary,
        // Error colors
        error = AppColors.primaryRed,
        onError = Color.White,
        errorContainer = AppColors.primaryRed.copy(alpha = 0.1f),
        onErrorContainer = AppColors.primaryRed,
        // Outline
        outline = AppColors.separator,
        outlineVariant = AppColors.divider,
    )

/**
 * Dark Color Scheme - RunAnywhere Brand Theme
 * Modern dark theme matching RunAnywhere.ai website
 */
private val DarkColorScheme =
    darkColorScheme(
        // Primary colors
        primary = AppColors.primaryAccent,
        onPrimary = Color.White,
        primaryContainer = AppColors.primaryAccent.copy(alpha = 0.2f),
        onPrimaryContainer = AppColors.primaryAccent,
        // Secondary colors
        secondary = AppColors.primaryPurple,
        onSecondary = Color.White,
        secondaryContainer = AppColors.primaryPurple.copy(alpha = 0.2f),
        onSecondaryContainer = AppColors.primaryPurple,
        // Tertiary colors
        tertiary = AppColors.primaryGreen,
        onTertiary = Color.White,
        tertiaryContainer = AppColors.primaryGreen.copy(alpha = 0.2f),
        onTertiaryContainer = AppColors.primaryGreen,
        // Background colors
        background = AppColors.backgroundGroupedDark,
        onBackground = Color.White,
        // Surface colors
        surface = AppColors.backgroundPrimaryDark,
        onSurface = Color.White,
        surfaceVariant = AppColors.backgroundSecondaryDark,
        onSurfaceVariant = Color.White.copy(alpha = 0.6f),
        // Error colors
        error = AppColors.primaryRed,
        onError = Color.White,
        errorContainer = AppColors.primaryRed.copy(alpha = 0.2f),
        onErrorContainer = AppColors.primaryRed,
        // Outline
        outline = AppColors.separator,
        outlineVariant = AppColors.dividerDark,
    )

@Composable
fun RunAnywhereAITheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    // Dynamic color disabled to maintain RunAnywhere brand consistency
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colorScheme =
        when {
            dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                val context = LocalContext.current
                if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            }
            darkTheme -> DarkColorScheme
            else -> LightColorScheme
        }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content,
    )
}
