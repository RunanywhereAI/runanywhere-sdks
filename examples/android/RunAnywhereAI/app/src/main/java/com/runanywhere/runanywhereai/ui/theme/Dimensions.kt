package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.ui.unit.dp

/**
 * Comprehensive dimension system matching iOS ChatInterfaceView exactly
 * Reference: iOS ChatInterfaceView.swift design specifications
 * All values extracted from iOS implementation for pixel-perfect Android replication
 */
object Dimensions {
    // ====================
    // PADDING VALUES
    // ====================
    val xxSmall = 2.dp
    val xSmall = 4.dp
    val small = 6.dp
    val smallMedium = 8.dp
    val medium = 10.dp
    val mediumLarge = 12.dp
    val regular = 14.dp
    val large = 16.dp
    val xLarge = 20.dp
    val xxLarge = 30.dp
    val xxxLarge = 40.dp
    val huge = 40.dp

    // Specific paddings
    val padding4 = 4.dp
    val padding6 = 6.dp
    val padding8 = 8.dp
    val padding9 = 9.dp
    val padding10 = 10.dp
    val padding12 = 12.dp
    val padding14 = 14.dp
    val padding15 = 15.dp
    val padding16 = 16.dp
    val padding20 = 20.dp
    val padding30 = 30.dp
    val padding40 = 40.dp
    val padding60 = 60.dp
    val padding100 = 100.dp

    // ====================
    // CORNER RADIUS
    // ====================
    val cornerRadiusSmall = 4.dp
    val cornerRadiusMedium = 6.dp
    val cornerRadiusRegular = 8.dp
    val cornerRadiusLarge = 10.dp
    val cornerRadiusXLarge = 12.dp
    val cornerRadiusXXLarge = 14.dp
    val cornerRadiusCard = 16.dp
    val cornerRadiusBubble = 18.dp
    val cornerRadiusModal = 20.dp

    // ====================
    // ICON SIZES
    // ====================
    val iconSmall = 8.dp
    val iconRegular = 18.dp
    val iconMedium = 28.dp
    val iconLarge = 48.dp
    val iconXLarge = 60.dp
    val iconXXLarge = 72.dp
    val iconHuge = 80.dp

    // ====================
    // BUTTON HEIGHTS
    // ====================
    val buttonHeightSmall = 28.dp
    val buttonHeightRegular = 44.dp
    val buttonHeightLarge = 72.dp

    // ====================
    // FRAME SIZES
    // ====================
    val minFrameHeight = 150.dp
    val maxFrameHeight = 150.dp

    // ====================
    // STROKE WIDTHS
    // ====================
    val strokeThin = 0.5.dp
    val strokeRegular = 1.dp
    val strokeMedium = 2.dp

    // ====================
    // SHADOW RADIUS
    // ====================
    val shadowSmall = 2.dp
    val shadowMedium = 3.dp
    val shadowLarge = 4.dp
    val shadowXLarge = 10.dp

    // ====================
    // CHAT-SPECIFIC DIMENSIONS
    // ====================

    // Message Bubbles
    val messageBubbleCornerRadius = cornerRadiusBubble // 18.dp
    val messageBubblePaddingHorizontal = padding16 // 16.dp
    val messageBubblePaddingVertical = padding12 // 12.dp
    val messageBubbleShadowRadius = shadowLarge // 4.dp
    val messageBubbleMinSpacing = padding60 // 60.dp (for alignment)
    val messageSpacingBetween = large // 16.dp

    // Thinking Section
    val thinkingSectionCornerRadius = mediumLarge // 12.dp
    val thinkingSectionPaddingHorizontal = regular // 14.dp
    val thinkingSectionPaddingVertical = padding9 // 9.dp
    val thinkingContentCornerRadius = medium // 10.dp
    val thinkingContentPadding = mediumLarge // 12.dp
    val thinkingContentMaxHeight = minFrameHeight // 150.dp

    // Model Badge
    val modelBadgePaddingHorizontal = medium // 10.dp
    val modelBadgePaddingVertical = 5.dp
    val modelBadgeCornerRadius = regular // 14.dp
    val modelBadgeSpacing = smallMedium // 8.dp

    // Model Info Bar
    val modelInfoBarPaddingHorizontal = large // 16.dp
    val modelInfoBarPaddingVertical = small // 6.dp
    val modelInfoFrameworkBadgeCornerRadius = cornerRadiusSmall // 4.dp
    val modelInfoFrameworkBadgePaddingHorizontal = small // 6.dp
    val modelInfoFrameworkBadgePaddingVertical = xSmall // 2.dp
    val modelInfoStatsIconTextSpacing = 3.dp
    val modelInfoStatsItemSpacing = mediumLarge // 12.dp

    // Input Area
    val inputAreaPadding = large // 16.dp
    val inputFieldButtonSpacing = mediumLarge // 12.dp
    val sendButtonSize = iconMedium // 28.dp

    // Typing Indicator
    val typingIndicatorDotSize = iconSmall // 8.dp
    val typingIndicatorDotSpacing = xSmall // 4.dp
    val typingIndicatorPaddingHorizontal = mediumLarge // 12.dp
    val typingIndicatorPaddingVertical = smallMedium // 8.dp
    val typingIndicatorCornerRadius = medium // 10.dp
    val typingIndicatorTextSpacing = mediumLarge // 12.dp

    // Empty State
    val emptyStateIconSize = iconXLarge // 60.dp
    val emptyStateIconTextSpacing = large // 16.dp
    val emptyStateTitleSubtitleSpacing = smallMedium // 8.dp

    // Toolbar
    val toolbarButtonSpacing = smallMedium // 8.dp
    val toolbarHeight = buttonHeightRegular // 44.dp

    // ====================
    // MAX WIDTHS
    // ====================
    val messageBubbleMaxWidth = 280.dp
    val maxContentWidth = 700.dp
}
