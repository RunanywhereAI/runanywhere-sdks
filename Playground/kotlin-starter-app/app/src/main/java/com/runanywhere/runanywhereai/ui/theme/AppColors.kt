package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * RunAnywhere Brand Color Palette
 * Color scheme matching RunAnywhere.ai website
 * Primary accent: Vibrant orange-red (#FF5500) - matches website branding
 * Dark theme backgrounds: Deep dark blue-gray matching website aesthetic
 */
object AppColors {
    // ====================
    // PRIMARY ACCENT COLORS - RunAnywhere Brand Colors
    // ====================
    // Primary brand color - vibrant orange/red from RunAnywhere.ai website
    val primaryAccent = Color(0xFFFF5500) // Vibrant orange-red - primary brand color
    val primaryOrange = Color(0xFFFF5500) // Same as primary accent
    val primaryBlue = Color(0xFF3B82F6) // Blue-500 - for secondary elements
    val primaryGreen = Color(0xFF10B981) // Emerald-500 - success green
    val primaryRed = Color(0xFFEF4444) // Red-500 - error red
    val primaryYellow = Color(0xFFEAB308) // Yellow-500
    val primaryPurple = Color(0xFF8B5CF6) // Violet-500 - purple accent

    // ====================
    // TEXT COLORS - RunAnywhere Theme
    // ====================
    val textPrimary = Color(0xFF0F172A) // Slate-900 - dark text for light mode
    val textSecondary = Color(0xFF475569) // Slate-600 - secondary text
    val textTertiary = Color(0xFF94A3B8) // Slate-400 - tertiary text
    val textWhite = Color.White

    // ====================
    // BACKGROUND COLORS - RunAnywhere Theme
    // ====================
    // Light mode - clean, modern backgrounds
    val backgroundPrimary = Color(0xFFFFFFFF) // Pure white
    val backgroundSecondary = Color(0xFFF8FAFC) // Slate-50 - very light gray
    val backgroundTertiary = Color(0xFFFFFFFF) // Pure white
    val backgroundGrouped = Color(0xFFF1F5F9) // Slate-100 - light grouped background
    val backgroundGray5 = Color(0xFFE2E8F0) // Slate-200 - light gray
    val backgroundGray6 = Color(0xFFF1F5F9) // Slate-100 - lighter gray

    // Dark mode - matching RunAnywhere.ai website dark theme
    val backgroundPrimaryDark = Color(0xFF0F172A) // Deep dark blue-gray - main background
    val backgroundSecondaryDark = Color(0xFF1A1F2E) // Slightly lighter dark surface
    val backgroundTertiaryDark = Color(0xFF252B3A) // Medium dark surface
    val backgroundGroupedDark = Color(0xFF0F172A) // Deep dark - grouped background
    val backgroundGray5Dark = Color(0xFF2A3142) // Medium dark gray
    val backgroundGray6Dark = Color(0xFF353B4A) // Lighter dark gray

    // ====================
    // MESSAGE BUBBLE COLORS - RunAnywhere Theme
    // ====================
    // User bubbles (with gradient support) - using vibrant orange/red brand color
    val userBubbleGradientStart = primaryAccent // Vibrant orange-red
    val userBubbleGradientEnd = Color(0xFFE64500) // Slightly darker orange-red
    val messageBubbleUser = primaryAccent // Vibrant orange-red

    // Assistant bubbles - clean gray
    val messageBubbleAssistant = backgroundGray5 // Slate-200
    val messageBubbleAssistantGradientStart = backgroundGray5
    val messageBubbleAssistantGradientEnd = backgroundGray6

    // Dark mode - toned down variant for reduced eye strain in low-light
    val messageBubbleUserDark = Color(0xFFCC4400) // Darker orange-red (80% brightness of primaryAccent)
    val messageBubbleAssistantDark = backgroundGray5Dark // Dark gray

    // ====================
    // BADGE/TAG COLORS
    // ====================
    val badgePrimary = primaryAccent.copy(alpha = 0.2f) // Brand primary (orange-red)
    val badgeGreen = primaryGreen.copy(alpha = 0.2f)
    val badgePurple = primaryPurple.copy(alpha = 0.2f)
    val badgeOrange = primaryOrange.copy(alpha = 0.2f)
    val badgeYellow = primaryYellow.copy(alpha = 0.2f)
    val badgeRed = primaryRed.copy(alpha = 0.2f)
    val badgeGray = Color.Gray.copy(alpha = 0.2f)

    // ====================
    // MODEL INFO COLORS - RunAnywhere Theme
    // ====================
    val modelFrameworkBg = primaryAccent.copy(alpha = 0.1f) // Brand primary orange-red
    val modelThinkingBg = primaryAccent.copy(alpha = 0.1f) // Brand primary orange-red

    // ====================
    // THINKING MODE COLORS - RunAnywhere Theme
    // ====================
    // Using brand orange for thinking mode to match website aesthetic
    val thinkingBackground = primaryAccent.copy(alpha = 0.1f) // 10% orange-red
    val thinkingBackgroundGradientStart = primaryAccent.copy(alpha = 0.1f)
    val thinkingBackgroundGradientEnd = primaryAccent.copy(alpha = 0.05f) // 5% orange-red
    val thinkingBorder = primaryAccent.copy(alpha = 0.2f)
    val thinkingContentBackground = backgroundGray6
    val thinkingProgressBackground = primaryAccent.copy(alpha = 0.12f)
    val thinkingProgressBackgroundGradientEnd = primaryAccent.copy(alpha = 0.06f)

    // Dark mode
    val thinkingBackgroundDark = primaryAccent.copy(alpha = 0.15f)
    val thinkingContentBackgroundDark = backgroundGray6Dark

    // ====================
    // STATUS COLORS - RunAnywhere Theme
    // ====================
    val statusGreen = primaryGreen
    val statusOrange = primaryOrange
    val statusRed = primaryRed
    val statusGray = Color(0xFF64748B) // Slate-500 - modern gray
    val statusPrimary = primaryAccent // Brand primary (orange-red)

    // Warning color - matches iOS orange for error states
    val warningOrange = primaryOrange

    // ====================
    // SHADOW COLORS
    // ====================
    val shadowDefault = Color.Black.copy(alpha = 0.1f)
    val shadowLight = Color.Black.copy(alpha = 0.1f)
    val shadowMedium = Color.Black.copy(alpha = 0.12f)
    val shadowDark = Color.Black.copy(alpha = 0.3f)

    // Shadows for specific components
    val shadowBubble = shadowMedium // 0.12 alpha
    val shadowThinking = primaryAccent.copy(alpha = 0.2f) // Orange-red glow
    val shadowModelBadge = primaryAccent.copy(alpha = 0.3f) // Brand primary
    val shadowTypingIndicator = shadowLight

    // ====================
    // OVERLAY COLORS
    // ====================
    val overlayLight = Color.Black.copy(alpha = 0.3f)
    val overlayMedium = Color.Black.copy(alpha = 0.4f)
    val overlayDark = Color.Black.copy(alpha = 0.7f)

    // ====================
    // BORDER COLORS - RunAnywhere Theme
    // ====================
    val borderLight = Color.White.copy(alpha = 0.3f)
    val borderMedium = Color.Black.copy(alpha = 0.05f)
    val separator = Color(0xFFE2E8F0) // Slate-200 - modern separator

    // ====================
    // DIVIDERS - RunAnywhere Theme
    // ====================
    val divider = Color(0xFFCBD5E1) // Slate-300 - light divider
    val dividerDark = Color(0xFF2A3142) // Dark divider matching website

    // ====================
    // CARDS & SURFACES
    // ====================
    val cardBackground = backgroundSecondary
    val cardBackgroundDark = backgroundSecondaryDark

    // ====================
    // TYPING INDICATOR - RunAnywhere Theme
    // ====================
    val typingIndicatorDots = primaryAccent.copy(alpha = 0.7f) // Brand primary
    val typingIndicatorBackground = backgroundGray5
    val typingIndicatorBorder = borderLight
    val typingIndicatorText = textSecondary.copy(alpha = 0.8f)

    // ====================
    // GRADIENT HELPERS
    // ====================

    /**
     * User message bubble gradient (orange-red brand color)
     */
    fun userBubbleGradient() =
        Brush.linearGradient(
            colors = listOf(userBubbleGradientStart, userBubbleGradientEnd),
        )

    /**
     * Assistant message bubble gradient (gray) - non-composable version for legacy use
     */
    fun assistantBubbleGradient() =
        Brush.linearGradient(
            colors = listOf(messageBubbleAssistantGradientStart, messageBubbleAssistantGradientEnd),
        )

    /**
     * Theme-aware assistant message bubble gradient
     * Uses dark gray in dark mode, light gray in light mode
     */
    @Composable
    fun assistantBubbleGradientThemed(): Brush {
        val isDark = isSystemInDarkTheme()
        return Brush.linearGradient(
            colors =
                if (isDark) {
                    listOf(backgroundGray5Dark, backgroundGray6Dark)
                } else {
                    listOf(messageBubbleAssistantGradientStart, messageBubbleAssistantGradientEnd)
                },
        )
    }

    /**
     * Theme-aware text color for assistant message bubbles
     * Returns white in dark mode, dark text in light mode
     */
    @Composable
    fun assistantBubbleTextColor(): Color {
        return if (isSystemInDarkTheme()) {
            Color.White
        } else {
            textPrimary
        }
    }

    /**
     * Thinking section background gradient (orange-red brand color)
     */
    fun thinkingBackgroundGradient() =
        Brush.linearGradient(
            colors = listOf(thinkingBackgroundGradientStart, thinkingBackgroundGradientEnd),
        )

    /**
     * Model badge gradient (brand primary)
     */
    fun modelBadgeGradient() =
        Brush.linearGradient(
            colors = listOf(primaryAccent, primaryAccent.copy(alpha = 0.9f)),
        )

    /**
     * Thinking progress gradient (orange-red brand color)
     */
    fun thinkingProgressGradient() =
        Brush.linearGradient(
            colors = listOf(thinkingProgressBackground, thinkingProgressBackgroundGradientEnd),
        )

    // ====================
    // HELPER FUNCTIONS
    // ====================

    /**
     * Get framework-specific badge color
     */
    fun frameworkBadgeColor(framework: String): Color {
        return when (framework.uppercase()) {
            "LLAMA_CPP", "LLAMACPP" -> primaryAccent.copy(alpha = 0.2f) // Brand primary
            "WHISPERKIT", "WHISPER" -> badgeGreen
            "MLKIT", "ML_KIT" -> badgePurple
            "COREML", "CORE_ML" -> badgeOrange
            else -> primaryAccent.copy(alpha = 0.2f)
        }
    }

    /**
     * Get framework-specific text color
     */
    fun frameworkTextColor(framework: String): Color {
        return when (framework.uppercase()) {
            "LLAMA_CPP", "LLAMACPP" -> primaryAccent // Brand primary
            "WHISPERKIT", "WHISPER" -> primaryGreen
            "MLKIT", "ML_KIT" -> primaryPurple
            "COREML", "CORE_ML" -> primaryOrange
            else -> primaryAccent
        }
    }
}
