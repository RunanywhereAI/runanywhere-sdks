package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * iOS-matching color palette for RunAnywhere AI
 * All colors are exact matches to iOS sample app design system
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Core/DesignSystem/AppColors.swift
 */
object AppColors {
    // ====================
    // PRIMARY ACCENT COLORS
    // ====================
    val primaryAccent = Color(0xFF007AFF)  // System accent color
    val primaryBlue = Color(0xFF007AFF)
    val primaryGreen = Color(0xFF34C759)
    val primaryRed = Color(0xFFFF3B30)
    val primaryOrange = Color(0xFFFF9500)  // Fixed typo from 0x0FF9500
    val primaryYellow = Color(0xFFFFCC00)
    val primaryPurple = Color(0xFF9C27B0)  // Updated to match iOS thinking mode

    // ====================
    // TEXT COLORS (iOS semantic colors)
    // ====================
    val textPrimary = Color(0xFF000000)  // Light mode
    val textSecondary = Color(0xFF3C3C43).copy(alpha = 0.6f)
    val textTertiary = Color(0xFF3C3C43).copy(alpha = 0.3f)
    val textWhite = Color.White

    // ====================
    // BACKGROUND COLORS
    // ====================
    // Light mode
    val backgroundPrimary = Color(0xFFFFFFFF)
    val backgroundSecondary = Color(0xFFF2F2F7)
    val backgroundTertiary = Color(0xFFFFFFFF)
    val backgroundGrouped = Color(0xFFF2F2F7)
    val backgroundGray5 = Color(0xFFE5E5EA)
    val backgroundGray6 = Color(0xFFF2F2F7)

    // Dark mode
    val backgroundPrimaryDark = Color(0xFF000000)
    val backgroundSecondaryDark = Color(0xFF1C1C1E)
    val backgroundTertiaryDark = Color(0xFF2C2C2E)
    val backgroundGroupedDark = Color(0xFF000000)
    val backgroundGray5Dark = Color(0xFF2C2C2E)
    val backgroundGray6Dark = Color(0xFF3A3A3C)

    // ====================
    // MESSAGE BUBBLE COLORS
    // ====================
    // User bubbles (with gradient support)
    val userBubbleGradientStart = primaryAccent
    val userBubbleGradientEnd = primaryAccent.copy(alpha = 0.9f)
    val messageBubbleUser = primaryBlue

    // Assistant bubbles
    val messageBubbleAssistant = backgroundGray5  // #E5E5EA
    val messageBubbleAssistantGradientStart = backgroundGray5
    val messageBubbleAssistantGradientEnd = backgroundGray6

    // Dark mode
    val messageBubbleUserDark = Color(0xFF0A84FF)
    val messageBubbleAssistantDark = backgroundGray5Dark

    // ====================
    // BADGE/TAG COLORS
    // ====================
    val badgeBlue = primaryBlue.copy(alpha = 0.2f)
    val badgeGreen = primaryGreen.copy(alpha = 0.2f)
    val badgePurple = primaryPurple.copy(alpha = 0.2f)
    val badgeOrange = primaryOrange.copy(alpha = 0.2f)
    val badgeYellow = primaryYellow.copy(alpha = 0.2f)
    val badgeRed = primaryRed.copy(alpha = 0.2f)
    val badgeGray = Color.Gray.copy(alpha = 0.2f)

    // ====================
    // MODEL INFO COLORS
    // ====================
    val modelFrameworkBg = primaryBlue.copy(alpha = 0.1f)
    val modelThinkingBg = primaryPurple.copy(alpha = 0.1f)

    // ====================
    // THINKING MODE COLORS
    // ====================
    val thinkingBackground = primaryPurple.copy(alpha = 0.1f)  // 10% purple
    val thinkingBackgroundGradientStart = primaryPurple.copy(alpha = 0.1f)
    val thinkingBackgroundGradientEnd = primaryPurple.copy(alpha = 0.05f)  // 5% purple
    val thinkingBorder = primaryPurple.copy(alpha = 0.2f)
    val thinkingContentBackground = backgroundGray6
    val thinkingProgressBackground = primaryPurple.copy(alpha = 0.12f)
    val thinkingProgressBackgroundGradientEnd = primaryPurple.copy(alpha = 0.06f)

    // Dark mode
    val thinkingBackgroundDark = primaryPurple.copy(alpha = 0.15f)
    val thinkingContentBackgroundDark = backgroundGray6Dark

    // ====================
    // STATUS COLORS
    // ====================
    val statusGreen = primaryGreen
    val statusOrange = primaryOrange
    val statusRed = primaryRed
    val statusGray = Color.Gray
    val statusBlue = primaryBlue

    // ====================
    // SHADOW COLORS
    // ====================
    val shadowDefault = Color.Black.copy(alpha = 0.1f)
    val shadowLight = Color.Black.copy(alpha = 0.1f)
    val shadowMedium = Color.Black.copy(alpha = 0.12f)
    val shadowDark = Color.Black.copy(alpha = 0.3f)

    // Shadows for specific components
    val shadowBubble = shadowMedium  // 0.12 alpha
    val shadowThinking = primaryPurple.copy(alpha = 0.2f)
    val shadowModelBadge = primaryBlue.copy(alpha = 0.3f)
    val shadowTypingIndicator = shadowLight

    // ====================
    // OVERLAY COLORS
    // ====================
    val overlayLight = Color.Black.copy(alpha = 0.3f)
    val overlayMedium = Color.Black.copy(alpha = 0.4f)
    val overlayDark = Color.Black.copy(alpha = 0.7f)

    // ====================
    // BORDER COLORS
    // ====================
    val borderLight = Color.White.copy(alpha = 0.3f)
    val borderMedium = Color.Black.copy(alpha = 0.05f)
    val separator = Color(0x3C3C4336)  // iOS separator color with alpha

    // ====================
    // DIVIDERS
    // ====================
    val divider = Color(0xFFC6C6C8)
    val dividerDark = Color(0xFF38383A)

    // ====================
    // CARDS & SURFACES
    // ====================
    val cardBackground = backgroundSecondary
    val cardBackgroundDark = backgroundSecondaryDark

    // ====================
    // TYPING INDICATOR
    // ====================
    val typingIndicatorDots = primaryBlue.copy(alpha = 0.7f)
    val typingIndicatorBackground = backgroundGray5
    val typingIndicatorBorder = borderLight
    val typingIndicatorText = textSecondary.copy(alpha = 0.8f)

    // ====================
    // GRADIENT HELPERS
    // ====================

    /**
     * User message bubble gradient (blue)
     */
    fun userBubbleGradient() = Brush.linearGradient(
        colors = listOf(userBubbleGradientStart, userBubbleGradientEnd)
    )

    /**
     * Assistant message bubble gradient (gray)
     */
    fun assistantBubbleGradient() = Brush.linearGradient(
        colors = listOf(messageBubbleAssistantGradientStart, messageBubbleAssistantGradientEnd)
    )

    /**
     * Thinking section background gradient (purple)
     */
    fun thinkingBackgroundGradient() = Brush.linearGradient(
        colors = listOf(thinkingBackgroundGradientStart, thinkingBackgroundGradientEnd)
    )

    /**
     * Model badge gradient (blue)
     */
    fun modelBadgeGradient() = Brush.linearGradient(
        colors = listOf(primaryBlue, primaryBlue.copy(alpha = 0.9f))
    )

    /**
     * Thinking progress gradient (purple)
     */
    fun thinkingProgressGradient() = Brush.linearGradient(
        colors = listOf(thinkingProgressBackground, thinkingProgressBackgroundGradientEnd)
    )

    // ====================
    // HELPER FUNCTIONS
    // ====================

    /**
     * Get framework-specific badge color
     */
    fun frameworkBadgeColor(framework: String): Color {
        return when (framework.uppercase()) {
            "LLAMA_CPP", "LLAMACPP" -> badgeBlue
            "WHISPERKIT", "WHISPER" -> badgeGreen
            "MLKIT", "ML_KIT" -> badgePurple
            "COREML", "CORE_ML" -> badgeOrange
            else -> badgeBlue
        }
    }

    /**
     * Get framework-specific text color
     */
    fun frameworkTextColor(framework: String): Color {
        return when (framework.uppercase()) {
            "LLAMA_CPP", "LLAMACPP" -> primaryBlue
            "WHISPERKIT", "WHISPER" -> primaryGreen
            "MLKIT", "ML_KIT" -> primaryPurple
            "COREML", "CORE_ML" -> primaryOrange
            else -> primaryBlue
        }
    }
}
