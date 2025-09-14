//
//  AppSpacing.swift
//  RunAnywhereAI
//
//  Centralized spacing and sizing from existing usage in the app
//

import SwiftUI

// MARK: - App Spacing (gathered from existing usage)
struct AppSpacing {

    // MARK: - Padding values (from existing usage)
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 6
    static let smallMedium: CGFloat = 8
    static let medium: CGFloat = 10
    static let mediumLarge: CGFloat = 12
    static let regular: CGFloat = 14
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 20
    static let xxLarge: CGFloat = 30
    static let xxxLarge: CGFloat = 40

    // Specific padding values used
    static let padding4: CGFloat = 4
    static let padding6: CGFloat = 6
    static let padding8: CGFloat = 8
    static let padding9: CGFloat = 9
    static let padding10: CGFloat = 10
    static let padding12: CGFloat = 12
    static let padding14: CGFloat = 14
    static let padding15: CGFloat = 15
    static let padding16: CGFloat = 16
    static let padding20: CGFloat = 20
    static let padding30: CGFloat = 30
    static let padding40: CGFloat = 40
    static let padding60: CGFloat = 60
    static let padding100: CGFloat = 100

    // MARK: - Component sizes (from existing usage)

    // Icon sizes
    static let iconSmall: CGFloat = 8
    static let iconRegular: CGFloat = 18
    static let iconMedium: CGFloat = 28
    static let iconLarge: CGFloat = 48
    static let iconXLarge: CGFloat = 60
    static let iconXXLarge: CGFloat = 72
    static let iconHuge: CGFloat = 80

    // Button sizes
    static let buttonHeightSmall: CGFloat = 28
    static let buttonHeightRegular: CGFloat = 44
    static let buttonHeightLarge: CGFloat = 72

    // Corner radius (from existing usage)
    static let cornerRadiusSmall: CGFloat = 4
    static let cornerRadiusMedium: CGFloat = 6
    static let cornerRadiusRegular: CGFloat = 8
    static let cornerRadiusLarge: CGFloat = 10
    static let cornerRadiusXLarge: CGFloat = 12
    static let cornerRadiusXXLarge: CGFloat = 14
    static let cornerRadiusCard: CGFloat = 16
    static let cornerRadiusBubble: CGFloat = 18
    static let cornerRadiusModal: CGFloat = 20

    // Frame sizes (from existing usage)
    static let minFrameHeight: CGFloat = 150
    static let maxFrameHeight: CGFloat = 150

    // Stroke widths
    static let strokeThin: CGFloat = 0.5
    static let strokeRegular: CGFloat = 1.0
    static let strokeMedium: CGFloat = 2.0

    // Shadow radius
    static let shadowSmall: CGFloat = 2
    static let shadowMedium: CGFloat = 3
    static let shadowLarge: CGFloat = 4
    static let shadowXLarge: CGFloat = 10
}

// MARK: - Layout Constants (from existing usage)
struct AppLayout {

    // macOS specific
    static let macOSMinWidth: CGFloat = 400
    static let macOSIdealWidth: CGFloat = 600
    static let macOSMaxWidth: CGFloat = 900
    static let macOSMinHeight: CGFloat = 300
    static let macOSIdealHeight: CGFloat = 500
    static let macOSMaxHeight: CGFloat = 800

    // Content width limits
    static let maxContentWidth: CGFloat = 800
    static let maxContentWidthLarge: CGFloat = 1000
    static let maxContentWidthXLarge: CGFloat = 1200

    // Sheet sizes
    static let sheetMinWidth: CGFloat = 500
    static let sheetIdealWidth: CGFloat = 600
    static let sheetMaxWidth: CGFloat = 700
    static let sheetMinHeight: CGFloat = 400
    static let sheetIdealHeight: CGFloat = 500
    static let sheetMaxHeight: CGFloat = 600

    // Animation durations
    static let animationFast: Double = 0.25
    static let animationRegular: Double = 0.3
    static let animationSlow: Double = 0.5
    static let animationVerySlow: Double = 0.6
    static let animationLoop: Double = 1.0
    static let animationLoopSlow: Double = 2.0
}
