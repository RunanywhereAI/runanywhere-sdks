//
//  AppColors.swift
//  YapRun
//
//  Brand color palette for YapRun.
//  Identity: black background, white as the primary voice.
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
}

struct AppColors {
    // Primary — white on black
    static let primaryAccent = Color.white
    static let primaryGreen  = Color(hex: 0x10B981)
    static let primaryRed    = Color(hex: 0xEF4444)

    // Backgrounds — dark theme
    static let backgroundPrimaryDark   = Color(hex: 0x000000)
    static let backgroundSecondaryDark = Color(hex: 0x0D0D0D)
    static let backgroundTertiaryDark  = Color(hex: 0x1A1A1A)
    static let backgroundGray5Dark     = Color(hex: 0x242424)
}
