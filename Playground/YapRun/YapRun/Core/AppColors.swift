//
//  AppColors.swift
//  YapRun
//
//  Brand color palette for YapRun.
//  All colors are adaptive — they flip between light and dark mode automatically.
//

import SwiftUI

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

    /// Adaptive color that switches between light and dark appearances.
    init(light: Color, dark: Color) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

struct AppColors {
    // Primary accent — adapts to theme
    static let primaryAccent = Color.primary
    static let primaryGreen  = Color(hex: 0x10B981)
    static let primaryRed    = Color(hex: 0xEF4444)

    // CTA
    static let ctaOrange = Color(hex: 0xF59E0B)

    // Backgrounds — adaptive
    static let backgroundPrimary = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x000000))
    static let backgroundSecondary = Color(light: Color(hex: 0xF2F2F7), dark: Color(hex: 0x0D0D0D))
    static let backgroundTertiary = Color(light: Color(hex: 0xE5E5EA), dark: Color(hex: 0x1A1A1A))
    static let backgroundGray5 = Color(light: Color(hex: 0xD1D1D6), dark: Color(hex: 0x242424))

    // Cards — adaptive
    static let cardBackground = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x141414))
    static let cardBorder = Color.primary.opacity(0.08)

    // Text hierarchy — adaptive (use .primary / .secondary for most cases)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary  = Color.primary.opacity(0.4)

    // Subtle overlays — adaptive (used for button backgrounds, dividers)
    static let overlayThin   = Color.primary.opacity(0.06)
    static let overlayLight  = Color.primary.opacity(0.08)
    static let overlayMedium = Color.primary.opacity(0.12)
    static let overlayThick  = Color.primary.opacity(0.15)

    // Legacy aliases (kept to minimize churn, map to adaptive versions)
    static let backgroundPrimaryDark = backgroundPrimary
    static let backgroundSecondaryDark = backgroundSecondary
    static let backgroundTertiaryDark = backgroundTertiary
    static let backgroundGray5Dark = backgroundGray5
}
