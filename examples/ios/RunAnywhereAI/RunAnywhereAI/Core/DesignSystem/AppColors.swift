//
//  AppColors.swift
//  RunAnywhereAI
//
//  Centralized colors from existing usage in the app
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// MARK: - App Colors (gathered from existing usage)
struct AppColors {

    // MARK: - Semantic Colors (already in use)
    static let primaryAccent = Color.accentColor
    static let primaryBlue = Color.blue
    static let primaryGreen = Color.green
    static let primaryRed = Color.red
    static let primaryOrange = Color.orange
    static let primaryPurple = Color.purple

    // MARK: - Text Colors (from existing usage)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textWhite = Color.white

    // MARK: - Background Colors (platform-specific, already in use)
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

    // MARK: - Component Colors (from existing usage)

    // Badge/Tag colors
    static let badgeBlue = Color.blue.opacity(0.2)
    static let badgeGreen = Color.green.opacity(0.2)
    static let badgePurple = Color.purple.opacity(0.2)
    static let badgeOrange = Color.orange.opacity(0.2)
    static let badgeRed = Color.red.opacity(0.2)
    static let badgeGray = Color.secondary.opacity(0.2)

    // Model info colors
    static let modelFrameworkBg = Color.blue.opacity(0.1)
    static let modelThinkingBg = Color.purple.opacity(0.1)

    // Chat bubble colors
    static let userBubbleGradientStart = Color.accentColor
    static let userBubbleGradientEnd = Color.accentColor.opacity(0.9)
    static let assistantBubbleBg = backgroundGray5

    // Status colors
    static let statusGreen = Color.green
    static let statusOrange = Color.orange
    static let statusRed = Color.red
    static let statusGray = Color.gray
    static let statusBlue = Color.blue

    // Shadow colors
    static let shadowDefault = Color.black.opacity(0.1)
    static let shadowLight = Color.black.opacity(0.1)
    static let shadowMedium = Color.black.opacity(0.12)
    static let shadowDark = Color.black.opacity(0.3)

    // Overlay colors
    static let overlayLight = Color.black.opacity(0.3)
    static let overlayMedium = Color.black.opacity(0.4)

    // Border colors
    static let borderLight = Color.white.opacity(0.3)
    static let borderMedium = Color.black.opacity(0.05)

    // Quiz specific
    static let quizTrue = Color.green
    static let quizFalse = Color.red
    static let quizCardShadow = Color.black.opacity(0.1)
}
