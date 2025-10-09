package com.runanywhere.runanywhereai.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * iOS-matching color palette for RunAnywhere AI
 * All colors are exact matches to iOS sample app design system
 * Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Core/DesignSystem/AppColors.swift
 */
object AppColors {
    // iOS System Colors (exact hex values from iOS design system)
    val primaryBlue = Color(0xFF007AFF)
    val primaryGreen = Color(0xFF34C759)
    val primaryRed = Color(0xFFFF3B30)
    val primaryOrange = Color(0xFF0FF9500)
    val primaryYellow = Color(0xFFFFCC00)
    val primaryPurple = Color(0xFFAF52DE)

    // Text Colors (iOS semantic colors)
    val textPrimary = Color(0xFF000000)
    val textSecondary = Color(0xFF3C3C43).copy(alpha = 0.6f)
    val textTertiary = Color(0xFF3C3C43).copy(alpha = 0.3f)

    // Backgrounds (Light mode)
    val backgroundPrimary = Color(0xFFFFFFFF)
    val backgroundSecondary = Color(0xFFF2F2F7)
    val backgroundTertiary = Color(0xFFFFFFFF)
    val backgroundGrouped = Color(0xFFF2F2F7)

    // Backgrounds (Dark mode)
    val backgroundPrimaryDark = Color(0xFF000000)
    val backgroundSecondaryDark = Color(0xFF1C1C1E)
    val backgroundTertiaryDark = Color(0xFF2C2C2E)
    val backgroundGroupedDark = Color(0xFF000000)

    // Message Bubbles (Light mode)
    val messageBubbleUser = Color(0xFF007AFF)  // Blue for user messages
    val messageBubbleAssistant = Color(0xFFE5E5EA)  // Gray for assistant messages

    // Message Bubbles (Dark mode)
    val messageBubbleUserDark = Color(0xFF0A84FF)
    val messageBubbleAssistantDark = Color(0xFF3A3A3C)

    // Framework Badges (with iOS-matching opacity)
    val badgeBlue = Color(0xFF007AFF).copy(alpha = 0.2f)
    val badgeGreen = Color(0xFF34C759).copy(alpha = 0.2f)
    val badgePurple = Color(0xFFAF52DE).copy(alpha = 0.2f)
    val badgeOrange = Color(0xFFFF9500).copy(alpha = 0.2f)
    val badgeYellow = Color(0xFFFFCC00).copy(alpha = 0.2f)
    val badgeRed = Color(0xFFFF3B30).copy(alpha = 0.2f)

    // Shadows & Overlays (iOS values)
    val shadowLight = Color.Black.copy(alpha = 0.1f)
    val shadowMedium = Color.Black.copy(alpha = 0.2f)
    val shadowHeavy = Color.Black.copy(alpha = 0.3f)
    val overlayLight = Color.Black.copy(alpha = 0.3f)
    val overlayDark = Color.Black.copy(alpha = 0.7f)

    // Dividers
    val divider = Color(0xFFC6C6C8)
    val dividerDark = Color(0xFF38383A)

    // Cards & Surfaces
    val cardBackground = backgroundSecondary
    val cardBackgroundDark = backgroundSecondaryDark

    // Thinking section (special background for AI thinking content)
    val thinkingBackground = backgroundSecondary.copy(alpha = 0.5f)
    val thinkingBackgroundDark = backgroundSecondaryDark.copy(alpha = 0.5f)

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
