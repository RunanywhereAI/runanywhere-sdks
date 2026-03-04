package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Comprehensive dimension system matching iOS ChatInterfaceView exactly.
 * All values are responsive — they scale with screen width via [rDp].
 * Design baseline: 360dp (standard phone).
 */
object Dimensions {
    // Padding Values
    val xxSmall: Dp @Composable get() = rDp(2.dp)
    val xSmall: Dp @Composable get() = rDp(4.dp)
    val small: Dp @Composable get() = rDp(6.dp)
    val smallMedium: Dp @Composable get() = rDp(8.dp)
    val medium: Dp @Composable get() = rDp(10.dp)
    val mediumLarge: Dp @Composable get() = rDp(12.dp)
    val regular: Dp @Composable get() = rDp(14.dp)
    val large: Dp @Composable get() = rDp(16.dp)
    val xLarge: Dp @Composable get() = rDp(20.dp)
    val xxLarge: Dp @Composable get() = rDp(30.dp)
    val xxxLarge: Dp @Composable get() = rDp(40.dp)
    val huge: Dp @Composable get() = rDp(40.dp)

    // Specific paddings
    val padding4: Dp @Composable get() = rDp(4.dp)
    val padding6: Dp @Composable get() = rDp(6.dp)
    val padding8: Dp @Composable get() = rDp(8.dp)
    val padding9: Dp @Composable get() = rDp(9.dp)
    val padding10: Dp @Composable get() = rDp(10.dp)
    val padding12: Dp @Composable get() = rDp(12.dp)
    val padding14: Dp @Composable get() = rDp(14.dp)
    val padding15: Dp @Composable get() = rDp(15.dp)
    val padding16: Dp @Composable get() = rDp(16.dp)
    val padding20: Dp @Composable get() = rDp(20.dp)
    val padding30: Dp @Composable get() = rDp(30.dp)
    val padding40: Dp @Composable get() = rDp(40.dp)
    val padding60: Dp @Composable get() = rDp(60.dp)
    val padding100: Dp @Composable get() = rDp(100.dp)

    // Corner Radius
    val cornerRadiusSmall: Dp @Composable get() = rDp(4.dp)
    val cornerRadiusMedium: Dp @Composable get() = rDp(6.dp)
    val cornerRadiusRegular: Dp @Composable get() = rDp(8.dp)
    val cornerRadiusLarge: Dp @Composable get() = rDp(10.dp)
    val cornerRadiusXLarge: Dp @Composable get() = rDp(12.dp)
    val cornerRadiusXXLarge: Dp @Composable get() = rDp(14.dp)
    val cornerRadiusCard: Dp @Composable get() = rDp(16.dp)
    val cornerRadiusBubble: Dp @Composable get() = rDp(18.dp)
    val cornerRadiusModal: Dp @Composable get() = rDp(20.dp)

    // Icon Sizes
    val iconSmall: Dp @Composable get() = rDp(8.dp)
    val iconRegular: Dp @Composable get() = rDp(18.dp)
    val iconMedium: Dp @Composable get() = rDp(28.dp)
    val iconLarge: Dp @Composable get() = rDp(48.dp)
    val iconXLarge: Dp @Composable get() = rDp(60.dp)
    val iconXXLarge: Dp @Composable get() = rDp(72.dp)
    val iconHuge: Dp @Composable get() = rDp(80.dp)

    // Button Heights
    val buttonHeightSmall: Dp @Composable get() = rDp(28.dp)
    val buttonHeightRegular: Dp @Composable get() = rDp(44.dp)
    val buttonHeightLarge: Dp @Composable get() = rDp(72.dp)

    // Frame Sizes
    val minFrameHeight: Dp @Composable get() = rDp(150.dp)
    val maxFrameHeight: Dp @Composable get() = rDp(150.dp)

    // Stroke Widths
    val strokeThin: Dp @Composable get() = rDp(0.5.dp)
    val strokeRegular: Dp @Composable get() = rDp(1.dp)
    val strokeMedium: Dp @Composable get() = rDp(2.dp)

    // Shadow Radius
    val shadowSmall: Dp @Composable get() = rDp(2.dp)
    val shadowMedium: Dp @Composable get() = rDp(3.dp)
    val shadowLarge: Dp @Composable get() = rDp(4.dp)
    val shadowXLarge: Dp @Composable get() = rDp(10.dp)

    // Chat-Specific Dimensions

    // Message Bubbles
    val messageBubbleCornerRadius: Dp @Composable get() = rDp(18.dp)
    val messageBubblePaddingHorizontal: Dp @Composable get() = rDp(12.dp)
    val messageBubblePaddingVertical: Dp @Composable get() = rDp(10.dp)
    val messageBubbleShadowRadius: Dp @Composable get() = rDp(4.dp)
    val messageBubbleMinSpacing: Dp @Composable get() = rDp(60.dp)
    val messageSpacingBetween: Dp @Composable get() = rDp(12.dp)
    val messageMaxWidthFraction = 0.85f

    // Assistant message icon
    val assistantIconSize: Dp @Composable get() = rDp(20.dp)
    val assistantIconSpacing: Dp @Composable get() = rDp(10.dp)

    // User bubble
    val userBubbleCornerRadius: Dp @Composable get() = rDp(18.dp)

    // Thinking Section
    val thinkingSectionCornerRadius: Dp @Composable get() = rDp(12.dp)
    val thinkingSectionPaddingHorizontal: Dp @Composable get() = rDp(14.dp)
    val thinkingSectionPaddingVertical: Dp @Composable get() = rDp(9.dp)
    val thinkingContentCornerRadius: Dp @Composable get() = rDp(10.dp)
    val thinkingContentPadding: Dp @Composable get() = rDp(12.dp)
    val thinkingContentMaxHeight: Dp @Composable get() = rDp(150.dp)

    // Model Badge
    val modelBadgePaddingHorizontal: Dp @Composable get() = rDp(10.dp)
    val modelBadgePaddingVertical: Dp @Composable get() = rDp(5.dp)
    val modelBadgeCornerRadius: Dp @Composable get() = rDp(14.dp)
    val modelBadgeSpacing: Dp @Composable get() = rDp(8.dp)

    // Model Info Bar
    val modelInfoBarPaddingHorizontal: Dp @Composable get() = rDp(16.dp)
    val modelInfoBarPaddingVertical: Dp @Composable get() = rDp(6.dp)
    val modelInfoFrameworkBadgeCornerRadius: Dp @Composable get() = rDp(4.dp)
    val modelInfoFrameworkBadgePaddingHorizontal: Dp @Composable get() = rDp(6.dp)
    val modelInfoFrameworkBadgePaddingVertical: Dp @Composable get() = rDp(2.dp)
    val modelInfoStatsIconTextSpacing: Dp @Composable get() = rDp(3.dp)
    val modelInfoStatsItemSpacing: Dp @Composable get() = rDp(12.dp)

    // Input Area
    val inputAreaPadding: Dp @Composable get() = rDp(16.dp)
    val inputFieldButtonSpacing: Dp @Composable get() = rDp(12.dp)
    val sendButtonSize: Dp @Composable get() = rDp(28.dp)

    // Typing Indicator
    val typingIndicatorDotSize: Dp @Composable get() = rDp(8.dp)
    val typingIndicatorDotSpacing: Dp @Composable get() = rDp(4.dp)
    val typingIndicatorPaddingHorizontal: Dp @Composable get() = rDp(12.dp)
    val typingIndicatorPaddingVertical: Dp @Composable get() = rDp(8.dp)
    val typingIndicatorCornerRadius: Dp @Composable get() = rDp(10.dp)
    val typingIndicatorTextSpacing: Dp @Composable get() = rDp(12.dp)

    // Empty State
    val emptyStateIconSize: Dp @Composable get() = rDp(60.dp)
    val emptyStateIconTextSpacing: Dp @Composable get() = rDp(16.dp)
    val emptyStateTitleSubtitleSpacing: Dp @Composable get() = rDp(8.dp)

    // Toolbar
    val toolbarButtonSpacing: Dp @Composable get() = rDp(8.dp)
    val toolbarHeight: Dp @Composable get() = rDp(44.dp)

    // Max Widths
    val messageBubbleMaxWidth: Dp @Composable get() = rDp(280.dp)
    val maxContentWidth: Dp @Composable get() = rDp(700.dp)
    val contextMenuMaxWidth: Dp @Composable get() = rDp(280.dp)

    // LoRA
    val loraScaleSliderHeight: Dp @Composable get() = rDp(32.dp)
}
