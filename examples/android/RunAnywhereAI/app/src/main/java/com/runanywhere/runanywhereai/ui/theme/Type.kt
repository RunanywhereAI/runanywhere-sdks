package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * Font family aligned with iOS.
 * iOS uses San Francisco (Font.system); Android uses system default sans (Roboto).
 * Set AppFontFamily to a custom FontFamily(Font(R.font.xxx)) to use a bundled font.
 */
private val AppFontFamily = FontFamily.Default

/**
 * iOS-matching typography system.
 * Font sizes and line heights match iOS AppTypography / SwiftUI text styles.
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Core/DesignSystem/Typography.swift
 * iOS point sizes (default): largeTitle 34, title 28, title2 22, title3 20, headline 17, body 17,
 * callout 16, subheadline 15, footnote 13, caption 12, caption2 11.
 */
val Typography =
    Typography(
        // iOS largeTitle (34pt bold)
        displayLarge =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.Bold,
                fontSize = 34.sp,
                lineHeight = 41.sp,
            ),
        // iOS title / Title 1 (28pt semibold)
        displayMedium =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 28.sp,
                lineHeight = 34.sp,
            ),
        // iOS title2 / Title 2 (22pt semibold)
        displaySmall =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 22.sp,
                lineHeight = 28.sp,
            ),
        // iOS title3 / Title 3 (20pt semibold)
        headlineLarge =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 20.sp,
                lineHeight = 25.sp,
            ),
        // iOS headline (17pt semibold) - Navigation titles
        headlineMedium =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 17.sp,
                lineHeight = 22.sp,
            ),
        headlineSmall =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                lineHeight = 20.sp,
            ),
        titleLarge =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 28.sp,
                lineHeight = 34.sp,
            ),
        // iOS title2 (22pt semibold)
        titleMedium =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 22.sp,
                lineHeight = 28.sp,
            ),
        // iOS title3 (20pt semibold)
        titleSmall =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.SemiBold,
                fontSize = 20.sp,
                lineHeight = 25.sp,
            ),
        // iOS body (17pt regular)
        bodyLarge =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.Normal,
                fontSize = 17.sp,
                lineHeight = 22.sp,
            ),
        // iOS subheadline (15pt regular)
        bodyMedium =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.Normal,
                fontSize = 15.sp,
                lineHeight = 20.sp,
            ),
        // iOS footnote (13pt regular)
        bodySmall =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.Normal,
                fontSize = 13.sp,
                lineHeight = 18.sp,
            ),
        labelLarge =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.Normal,
                fontSize = 15.sp,
                lineHeight = 20.sp,
            ),
        // iOS caption (12pt regular)
        labelMedium =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.Normal,
                fontSize = 12.sp,
                lineHeight = 16.sp,
            ),
        // iOS caption2 (11pt regular)
        labelSmall =
            TextStyle(
                fontFamily = AppFontFamily,
                fontWeight = FontWeight.Normal,
                fontSize = 11.sp,
                lineHeight = 13.sp,
            ),
    )

/**
 * Custom text styles matching iOS AppTypography.
 * Sizes: system9–system12, system14, system18, system28, system48, system60, system80.
 * Weights and semantics match Typography.swift.
 */
object AppTypography {
    private val fontFamily = FontFamily.Default

    // Custom sizes matching iOS exactly (Font.system(size: n))
    val system9 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 9.sp,
            lineHeight = 11.sp,
        )

    val system10 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 10.sp,
            lineHeight = 12.sp,
        )

    val system11 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 11.sp,
            lineHeight = 13.sp,
        )

    val system11Medium = system11.copy(fontWeight = FontWeight.Medium)

    val system12 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 12.sp,
            lineHeight = 16.sp,
        )

    val system12Medium = system12.copy(fontWeight = FontWeight.Medium)

    val system14 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 14.sp,
            lineHeight = 18.sp,
        )

    val system18 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 18.sp,
            lineHeight = 22.sp,
        )

    val system28 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 28.sp,
            lineHeight = 34.sp,
        )

    val system48 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 48.sp,
            lineHeight = 56.sp,
        )

    val system60 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 60.sp,
            lineHeight = 72.sp,
        )

    val system80 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 80.sp,
            lineHeight = 88.sp,
        )

    // iOS callout (16pt regular)
    val callout =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 16.sp,
            lineHeight = 21.sp,
        )

    // Weight variants (matching iOS)
    val caption =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 12.sp,
            lineHeight = 16.sp,
        )

    val caption2 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Normal,
            fontSize = 11.sp,
            lineHeight = 13.sp,
        )

    val caption2Medium = caption2.copy(fontWeight = FontWeight.Medium)

    val caption2Bold = caption2.copy(fontWeight = FontWeight.Bold)

    // Monospaced (iOS: Font.system(.body, design: .monospaced) / size 9 bold)
    val monospacedCaption =
        TextStyle(
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.Bold,
            fontSize = 9.sp,
            lineHeight = 11.sp,
        )

    // Rounded-style sizes (iOS: design: .rounded)
    val rounded10 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Medium,
            fontSize = 10.sp,
            lineHeight = 12.sp,
        )

    val rounded11 =
        TextStyle(
            fontFamily = fontFamily,
            fontWeight = FontWeight.Medium,
            fontSize = 11.sp,
            lineHeight = 13.sp,
        )
}
