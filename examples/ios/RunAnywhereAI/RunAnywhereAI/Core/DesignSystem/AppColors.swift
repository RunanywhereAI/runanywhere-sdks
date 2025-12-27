//
//  AppColors.swift
//  RunAnywhereAI
//
//  RunAnywhere Brand Color Palette
//  Color scheme matching RunAnywhere.ai website
//  Primary accent: Vibrant orange-red (#FF5500) - matches website branding
//  Dark theme backgrounds: Deep dark blue-gray matching website aesthetic
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

// MARK: - App Colors (RunAnywhere Brand Theme)
struct AppColors {
    // ====================
    // PRIMARY ACCENT COLORS - RunAnywhere Brand Colors
    // ====================
    // Primary brand color - vibrant orange/red from RunAnywhere.ai website
    static let primaryAccent = Color(hex: 0xFF5500)  // Vibrant orange-red - primary brand color
    static let primaryOrange = Color(hex: 0xFF5500)  // Same as primary accent
    static let primaryBlue = Color(hex: 0x3B82F6)    // Blue-500 - for secondary elements
    static let primaryGreen = Color(hex: 0x10B981)   // Emerald-500 - success green
    static let primaryRed = Color(hex: 0xEF4444)     // Red-500 - error red
    static let primaryYellow = Color(hex: 0xEAB308)  // Yellow-500
    static let primaryPurple = Color(hex: 0x8B5CF6)  // Violet-500 - purple accent

    // ====================
    // TEXT COLORS - RunAnywhere Theme
    // ====================
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(hex: 0x94A3B8)   // Slate-400 - tertiary text
    static let textWhite = Color.white

    // Light mode specific text colors
    static let textPrimaryLight = Color(hex: 0x0F172A)  // Slate-900 - dark text for light mode
    static let textSecondaryLight = Color(hex: 0x475569) // Slate-600 - secondary text

    // ====================
    // BACKGROUND COLORS - RunAnywhere Theme
    // ====================
    // Platform-adaptive backgrounds using system colors for proper dark mode support
    #if os(iOS)
    static let backgroundPrimary = Color(.systemBackground)
    static let backgroundSecondary = Color(.secondarySystemBackground)
    static let backgroundTertiary = Color(.tertiarySystemBackground)
    static let backgroundGrouped = Color(.systemGroupedBackground)
    static let backgroundGray5 = Color(.systemGray5)
    static let backgroundGray6 = Color(.systemGray6)
    static let separator = Color(.separator)
    #else
    static let backgroundPrimary = Color(NSColor.windowBackgroundColor)
    static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
    static let backgroundTertiary = Color(NSColor.textBackgroundColor)
    static let backgroundGrouped = Color(NSColor.controlBackgroundColor)
    static let backgroundGray5 = Color(NSColor.controlColor)
    static let backgroundGray6 = Color(NSColor.controlBackgroundColor)
    static let separator = Color(NSColor.separatorColor)
    #endif

    // Light mode explicit colors (for when you need exact control)
    static let backgroundPrimaryLight = Color(hex: 0xFFFFFF)   // Pure white
    static let backgroundSecondaryLight = Color(hex: 0xF8FAFC) // Slate-50 - very light gray
    static let backgroundGroupedLight = Color(hex: 0xF1F5F9)   // Slate-100 - light grouped background
    static let backgroundGray5Light = Color(hex: 0xE2E8F0)     // Slate-200 - light gray
    static let backgroundGray6Light = Color(hex: 0xF1F5F9)     // Slate-100 - lighter gray

    // Dark mode explicit colors - matching RunAnywhere.ai website dark theme
    static let backgroundPrimaryDark = Color(hex: 0x0F172A)    // Deep dark blue-gray - main background
    static let backgroundSecondaryDark = Color(hex: 0x1A1F2E)  // Slightly lighter dark surface
    static let backgroundTertiaryDark = Color(hex: 0x252B3A)   // Medium dark surface
    static let backgroundGroupedDark = Color(hex: 0x0F172A)    // Deep dark - grouped background
    static let backgroundGray5Dark = Color(hex: 0x2A3142)      // Medium dark gray
    static let backgroundGray6Dark = Color(hex: 0x353B4A)      // Lighter dark gray

    // ====================
    // MESSAGE BUBBLE COLORS - RunAnywhere Theme
    // ====================
    // User bubbles (with gradient support) - using vibrant orange/red brand color
    static let userBubbleGradientStart = primaryAccent         // Vibrant orange-red
    static let userBubbleGradientEnd = Color(hex: 0xE64500)    // Slightly darker orange-red
    static let messageBubbleUser = primaryAccent               // Vibrant orange-red

    // Assistant bubbles - clean gray (uses system colors for dark mode adaptation)
    static let assistantBubbleBg = backgroundGray5
    static let messageBubbleAssistant = backgroundGray5
    static let messageBubbleAssistantGradientStart = backgroundGray5
    static let messageBubbleAssistantGradientEnd = backgroundGray6

    // Dark mode - toned down variant for reduced eye strain in low-light
    static let messageBubbleUserDark = Color(hex: 0xCC4400)    // Darker orange-red (80% brightness)
    static let messageBubbleAssistantDark = backgroundGray5Dark // Dark gray

    // ====================
    // BADGE/TAG COLORS - RunAnywhere Theme
    // ====================
    static let badgePrimary = primaryAccent.opacity(0.2)       // Brand primary (orange-red)
    static let badgeBlue = primaryBlue.opacity(0.2)
    static let badgeGreen = primaryGreen.opacity(0.2)
    static let badgePurple = primaryPurple.opacity(0.2)
    static let badgeOrange = primaryOrange.opacity(0.2)
    static let badgeYellow = primaryYellow.opacity(0.2)
    static let badgeRed = primaryRed.opacity(0.2)
    static let badgeGray = Color.gray.opacity(0.2)

    // ====================
    // MODEL INFO COLORS - RunAnywhere Theme
    // ====================
    static let modelFrameworkBg = primaryAccent.opacity(0.1)   // Brand primary orange-red
    static let modelThinkingBg = primaryAccent.opacity(0.1)    // Brand primary orange-red

    // ====================
    // THINKING MODE COLORS - RunAnywhere Theme
    // ====================
    // Using brand orange for thinking mode to match website aesthetic
    static let thinkingBackground = primaryAccent.opacity(0.1)           // 10% orange-red
    static let thinkingBackgroundGradientStart = primaryAccent.opacity(0.1)
    static let thinkingBackgroundGradientEnd = primaryAccent.opacity(0.05) // 5% orange-red
    static let thinkingBorder = primaryAccent.opacity(0.2)
    static let thinkingContentBackground = backgroundGray6
    static let thinkingContentBackgroundColor = backgroundGray6
    static let thinkingProgressBackground = primaryAccent.opacity(0.12)
    static let thinkingProgressBackgroundGradientEnd = primaryAccent.opacity(0.06)

    // Dark mode thinking colors
    static let thinkingBackgroundDark = primaryAccent.opacity(0.15)
    static let thinkingContentBackgroundDark = backgroundGray6Dark

    // ====================
    // STATUS COLORS - RunAnywhere Theme
    // ====================
    static let statusGreen = primaryGreen
    static let statusOrange = primaryOrange
    static let statusRed = primaryRed
    static let statusGray = Color(hex: 0x64748B)  // Slate-500 - modern gray
    static let statusBlue = primaryBlue
    static let statusPrimary = primaryAccent      // Brand primary (orange-red)

    // Warning color - matches brand orange for error states
    static let warningOrange = primaryOrange

    // ====================
    // SHADOW COLORS
    // ====================
    static let shadowDefault = Color.black.opacity(0.1)
    static let shadowLight = Color.black.opacity(0.1)
    static let shadowMedium = Color.black.opacity(0.12)
    static let shadowDark = Color.black.opacity(0.3)

    // Shadows for specific components
    static let shadowBubble = shadowMedium  // 0.12 alpha
    static let shadowThinking = primaryAccent.opacity(0.2)     // Orange-red glow
    static let shadowModelBadge = primaryAccent.opacity(0.3)   // Brand primary
    static let shadowTypingIndicator = shadowLight

    // ====================
    // OVERLAY COLORS
    // ====================
    static let overlayLight = Color.black.opacity(0.3)
    static let overlayMedium = Color.black.opacity(0.4)
    static let overlayDark = Color.black.opacity(0.7)

    // ====================
    // BORDER COLORS - RunAnywhere Theme
    // ====================
    static let borderLight = Color.white.opacity(0.3)
    static let borderMedium = Color.black.opacity(0.05)
    static let separatorColor = Color(hex: 0xE2E8F0)  // Slate-200 - modern separator

    // ====================
    // DIVIDERS - RunAnywhere Theme
    // ====================
    static let divider = Color(hex: 0xCBD5E1)         // Slate-300 - light divider
    static let dividerDark = Color(hex: 0x2A3142)     // Dark divider matching website

    // ====================
    // CARDS & SURFACES
    // ====================
    static let cardBackground = backgroundSecondary
    static let cardBackgroundDark = backgroundSecondaryDark

    // ====================
    // TYPING INDICATOR - RunAnywhere Theme
    // ====================
    static let typingIndicatorDots = primaryAccent.opacity(0.7)  // Brand primary
    static let typingIndicatorBackground = backgroundGray5
    static let typingIndicatorBorder = borderLight
    static let typingIndicatorText = textSecondary.opacity(0.8)

    // ====================
    // QUIZ SPECIFIC
    // ====================
    static let quizTrue = primaryGreen
    static let quizFalse = primaryRed
    static let quizCardShadow = Color.black.opacity(0.1)

    // ====================
    // FRAMEWORK-SPECIFIC BADGE COLORS
    // ====================
    static func frameworkBadgeColor(framework: String) -> Color {
        switch framework.uppercased() {
        case "LLAMA_CPP", "LLAMACPP":
            return primaryAccent.opacity(0.2)  // Brand primary
        case "MLKIT", "ML_KIT":
            return badgePurple
        case "COREML", "CORE_ML":
            return badgeOrange
        default:
            return primaryAccent.opacity(0.2)
        }
    }

    static func frameworkTextColor(framework: String) -> Color {
        switch framework.uppercased() {
        case "LLAMA_CPP", "LLAMACPP":
            return primaryAccent  // Brand primary
        case "MLKIT", "ML_KIT":
            return primaryPurple
        case "COREML", "CORE_ML":
            return primaryOrange
        default:
            return primaryAccent
        }
    }
}
