package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.ui.unit.dp

/**
 * iOS-matching spacing system for RunAnywhere AI
 * All values are exact matches to iOS sample app design system
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Core/DesignSystem/AppSpacing.swift
 */
object AppSpacing {
    // Base spacing scale (matching iOS exactly in points -> dp)
    val xxSmall = 2.dp
    val xSmall = 4.dp
    val small = 8.dp
    val smallMedium = 10.dp
    val medium = 12.dp
    val padding15 = 15.dp
    val large = 16.dp
    val xLarge = 20.dp
    val xxLarge = 24.dp
    val xxxLarge = 32.dp
    val huge = 40.dp
    val padding48 = 48.dp
    val padding64 = 64.dp
    val padding80 = 80.dp
    val padding100 = 100.dp

    // Corner Radius (iOS values)
    val cornerRadiusSmall = 8.dp
    val cornerRadiusMedium = 12.dp
    val cornerRadiusLarge = 16.dp
    val cornerRadiusXLarge = 20.dp
    val cornerRadiusXXLarge = 24.dp

    // Layout constraints (iOS max widths)
    val maxContentWidth = 700.dp
    val maxContentWidthLarge = 900.dp
    val messageBubbleMaxWidth = 280.dp

    // Component-specific sizes
    val buttonHeight = 44.dp // iOS standard button height
    val buttonHeightSmall = 32.dp
    val buttonHeightLarge = 56.dp

    val micButtonSize = 80.dp // Large mic button for voice input
    val modelBadgeHeight = 32.dp
    val progressBarHeight = 4.dp
    val dividerThickness = 0.5.dp // iOS hairline divider

    // Icon sizes
    val iconSizeSmall = 16.dp
    val iconSizeMedium = 24.dp
    val iconSizeLarge = 32.dp
    val iconSizeXLarge = 48.dp

    // Minimum touch targets (accessibility)
    val minTouchTarget = 44.dp // iOS minimum for accessibility

    // Animation durations (in milliseconds, matching iOS)
    const val animationFast = 200
    const val animationNormal = 300
    const val animationSlow = 400
    const val animationSpringSlow = 600

    // List item heights
    val listItemHeightSmall = 44.dp
    val listItemHeightMedium = 56.dp
    val listItemHeightLarge = 72.dp

    // Card padding
    val cardPaddingSmall = small
    val cardPaddingMedium = medium
    val cardPaddingLarge = large

    // Screen padding (safe area insets)
    val screenPaddingHorizontal = large
    val screenPaddingVertical = xLarge

    // Spacing between sections
    val sectionSpacing = xxLarge
    val itemSpacing = medium

    // Message bubble specific
    val messagePadding = medium
    val messageSpacing = small
    val thinkingPadding = small

    // Model card specific
    val modelCardPadding = large
    val modelCardSpacing = small
    val modelImageSize = 48.dp

    // Settings screen specific
    val settingsSectionSpacing = xxLarge
    val settingsItemHeight = 56.dp
    val settingsSliderPadding = medium
}
