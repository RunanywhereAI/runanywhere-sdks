//
//  PaytmTheme.swift
//  RunAnywhereAI
//
//  Created for VSS Demo on 7/22/25.
//

import SwiftUI

struct PaytmTheme {
    // Paytm Official Colors
    static let primaryBlue = Color(red: 0/255, green: 46/255, blue: 110/255)  // #002E6E
    static let secondaryBlue = Color(red: 0/255, green: 185/255, blue: 241/255)  // #00B9F1
    static let lightBlue = Color(red: 233/255, green: 247/255, blue: 255/255)  // #E9F7FF
    static let darkText = Color(red: 26/255, green: 26/255, blue: 26/255)  // #1A1A1A
    static let grayText = Color(red: 102/255, green: 102/255, blue: 102/255)  // #666666
    static let successGreen = Color(red: 76/255, green: 175/255, blue: 80/255)  // #4CAF50
    static let warningOrange = Color(red: 255/255, green: 152/255, blue: 0/255)  // #FF9800

    // Gradients
    static let primaryGradient = LinearGradient(
        colors: [primaryBlue, secondaryBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [Color.white, lightBlue.opacity(0.3)],
        startPoint: .top,
        endPoint: .bottom
    )

    // Typography
    static func headlineFont(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func bodyFont(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func captionFont(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    // Card Styling
    static func cardStyle() -> some ViewModifier {
        CardStyleModifier()
    }
}

struct CardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func paytmCard() -> some View {
        modifier(CardStyleModifier())
    }
}
