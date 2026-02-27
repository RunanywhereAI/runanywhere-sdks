package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * iOS-matching spacing system for RunAnywhere AI.
 * All values are responsive — they scale with screen width via [rDp].
 * Design baseline: 360dp (standard phone).
 */
object AppSpacing {
    // Base spacing scale (matching iOS exactly in points -> dp)
    val xxSmall: Dp @Composable get() = rDp(2.dp)
    val xSmall: Dp @Composable get() = rDp(4.dp)
    val small: Dp @Composable get() = rDp(8.dp)
    val smallMedium: Dp @Composable get() = rDp(10.dp)
    val medium: Dp @Composable get() = rDp(12.dp)
    val padding15: Dp @Composable get() = rDp(15.dp)
    val large: Dp @Composable get() = rDp(16.dp)
    val xLarge: Dp @Composable get() = rDp(20.dp)
    val xxLarge: Dp @Composable get() = rDp(24.dp)
    val xxxLarge: Dp @Composable get() = rDp(32.dp)
    val huge: Dp @Composable get() = rDp(40.dp)
    val padding48: Dp @Composable get() = rDp(48.dp)
    val padding64: Dp @Composable get() = rDp(64.dp)
    val padding80: Dp @Composable get() = rDp(80.dp)
    val padding100: Dp @Composable get() = rDp(100.dp)

    // Corner Radius (iOS values)
    val cornerRadiusSmall: Dp @Composable get() = rDp(8.dp)
    val cornerRadiusMedium: Dp @Composable get() = rDp(12.dp)
    val cornerRadiusLarge: Dp @Composable get() = rDp(16.dp)
    val cornerRadiusXLarge: Dp @Composable get() = rDp(20.dp)
    val cornerRadiusXXLarge: Dp @Composable get() = rDp(24.dp)

    // Layout constraints (iOS max widths)
    val maxContentWidth: Dp @Composable get() = rDp(700.dp)
    val maxContentWidthLarge: Dp @Composable get() = rDp(900.dp)
    val messageBubbleMaxWidth: Dp @Composable get() = rDp(280.dp)

    // Component-specific sizes
    val buttonHeight: Dp @Composable get() = rDp(44.dp)
    val buttonHeightSmall: Dp @Composable get() = rDp(32.dp)
    val buttonHeightLarge: Dp @Composable get() = rDp(56.dp)

    val micButtonSize: Dp @Composable get() = rDp(80.dp)
    val modelBadgeHeight: Dp @Composable get() = rDp(32.dp)
    val progressBarHeight: Dp @Composable get() = rDp(4.dp)
    val dividerThickness: Dp @Composable get() = rDp(0.5.dp)

    // Icon sizes
    val iconSizeSmall: Dp @Composable get() = rDp(16.dp)
    val iconSizeMedium: Dp @Composable get() = rDp(24.dp)
    val iconSizeLarge: Dp @Composable get() = rDp(32.dp)
    val iconSizeXLarge: Dp @Composable get() = rDp(48.dp)

    // Minimum touch targets (accessibility)
    val minTouchTarget: Dp @Composable get() = rDp(44.dp)

    // Animation durations (in milliseconds, matching iOS) — NOT responsive
    const val animationFast = 200
    const val animationNormal = 300
    const val animationSlow = 400
    const val animationSpringSlow = 600

    // List item heights
    val listItemHeightSmall: Dp @Composable get() = rDp(44.dp)
    val listItemHeightMedium: Dp @Composable get() = rDp(56.dp)
    val listItemHeightLarge: Dp @Composable get() = rDp(72.dp)

    // Card padding
    val cardPaddingSmall: Dp @Composable get() = small
    val cardPaddingMedium: Dp @Composable get() = medium
    val cardPaddingLarge: Dp @Composable get() = large

    // Screen padding (safe area insets)
    val screenPaddingHorizontal: Dp @Composable get() = large
    val screenPaddingVertical: Dp @Composable get() = xLarge

    // Spacing between sections
    val sectionSpacing: Dp @Composable get() = xxLarge
    val itemSpacing: Dp @Composable get() = medium

    // Message bubble specific
    val messagePadding: Dp @Composable get() = medium
    val messageSpacing: Dp @Composable get() = small
    val thinkingPadding: Dp @Composable get() = small

    // Model card specific
    val modelCardPadding: Dp @Composable get() = large
    val modelCardSpacing: Dp @Composable get() = small
    val modelImageSize: Dp @Composable get() = rDp(48.dp)

    // Settings screen specific
    val settingsSectionSpacing: Dp @Composable get() = xxLarge
    val settingsItemHeight: Dp @Composable get() = rDp(56.dp)
    val settingsSliderPadding: Dp @Composable get() = medium
}
