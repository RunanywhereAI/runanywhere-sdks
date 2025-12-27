//
//  Typography.swift
//  RunAnywhereAI
//
//  Centralized typography from existing usage in the app
//

import SwiftUI

// MARK: - App Typography (gathered from existing usage)
struct AppTypography {
    // MARK: - Existing font usage in the app

    // Large titles and displays
    static let largeTitle = Font.largeTitle
    static let title = Font.title
    static let title2 = Font.title2
    static let title3 = Font.title3

    // Headers
    static let headline = Font.headline
    static let subheadline = Font.subheadline

    // Body text
    static let body = Font.body
    static let callout = Font.callout
    static let footnote = Font.footnote

    // Small text
    static let caption = Font.caption
    static let caption2 = Font.caption2

    // Custom sizes (from existing usage)
    static let system9 = Font.system(size: 9)
    static let system10 = Font.system(size: 10)
    static let system11 = Font.system(size: 11)
    static let system12 = Font.system(size: 12)
    static let system14 = Font.system(size: 14)
    static let system18 = Font.system(size: 18)
    static let system28 = Font.system(size: 28)
    static let system48 = Font.system(size: 48)
    static let system60 = Font.system(size: 60)
    static let system80 = Font.system(size: 80)

    // With weights (from existing usage)
    static let headlineSemibold = Font.headline.weight(.semibold)
    static let subheadlineMedium = Font.subheadline.weight(.medium)
    static let subheadlineSemibold = Font.subheadline.weight(.semibold)
    static let captionMedium = Font.caption.weight(.medium)
    static let caption2Medium = Font.caption2.weight(.medium)
    static let caption2Bold = Font.caption2.weight(.bold)
    static let titleBold = Font.title.weight(.bold)
    static let title2Semibold = Font.title2.weight(.semibold)
    static let title3Medium = Font.title3.weight(.medium)
    static let largeTitleBold = Font.largeTitle.weight(.bold)

    // Design variants (from existing usage)
    static let monospaced = Font.system(.body, design: .monospaced)
    static let monospacedCaption = Font.system(size: 9, weight: .bold, design: .monospaced)
    static let rounded10 = Font.system(size: 10, weight: .medium, design: .rounded)
    static let rounded11 = Font.system(size: 11, weight: .medium, design: .rounded)
}
