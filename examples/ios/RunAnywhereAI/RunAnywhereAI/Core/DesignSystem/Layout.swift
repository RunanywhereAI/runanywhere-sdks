//
//  Layout.swift
//  RunAnywhereAI
//
//  The 4pt spacing grid, the radius scale, and the elevation scale.
//
//  This replaces `AppSpacing`'s `padding4 … padding100` / ten `cornerRadius*`
//  values. That list catalogued drift instead of constraining it: when every
//  number a view could want already has a name, "which one" stops being a
//  design decision and 177 raw `spacing:` literals appear anyway. A scale is
//  useful precisely because it is missing the values you shouldn't use.
//
//  Mac sits further from the eye and its type is a genuine step smaller
//  (see `AppType`), so the geometry around that type steps down with it —
//  otherwise a card keeps phone padding around shrunken text and a 1200pt
//  window shows what an iPhone does.
//

import SwiftUI

/// 4pt spacing grid. Every gap and inset in the app comes from here.
enum Space {
    /// 2 — hairline separation inside a single control (icon↔its own label).
    static let hair: CGFloat = 2
    /// 4 — tight pairs: a value and its unit, a label and its badge.
    static let xs: CGFloat = 4
    /// 8 — within a component: icon↔label, stacked lines of one idea.
    static let sm: CGFloat = 8
    /// 12 — between related rows inside a card.
    static let md: CGFloat = 12
    /// 16 — the default. Card padding, list row gaps, screen margins on phone.
    static let lg: CGFloat = 16
    /// 24 — between distinct groups in a screen.
    static let xl: CGFloat = 24
    /// 32 — between sections.
    static let xxl: CGFloat = 32
    /// 48 — around a lone hero element (empty states, onboarding).
    static let xxxl: CGFloat = 48

    /// Horizontal screen margin.
    #if os(macOS)
    static let screenMargin: CGFloat = 24
    #else
    static let screenMargin: CGFloat = 16
    #endif

    /// Internal padding of a card.
    #if os(macOS)
    static let cardPadding: CGFloat = 12
    #else
    static let cardPadding: CGFloat = 16
    #endif
}

/// Corner radius scale. Concentric with the platform's own geometry.
enum Radius {
    /// 6 — badges, chips, inline code.
    static let xs: CGFloat = 6
    /// 10 — buttons, small controls, list row highlights.
    static let sm: CGFloat = 10
    /// 14 — inner surfaces nested inside a card.
    static let md: CGFloat = 14
    /// Cards. Tighter on Mac, where 20pt beside AppKit's own chrome reads as a
    /// phone widget sitting in a Mac window rather than a Mac control.
    #if os(macOS)
    static let lg: CGFloat = 12
    /// Sheets, hero surfaces, the composer.
    static let xl: CGFloat = 16
    #else
    static let lg: CGFloat = 20
    /// Sheets, hero surfaces, the composer.
    static let xl: CGFloat = 28
    #endif
    /// A capsule, for the cases that need a number rather than `Capsule()`.
    static let pill: CGFloat = 999
}

/// A hairline that stays visually one pixel at any scale factor.
enum Hairline {
    static let width: CGFloat = 0.5
}

/// Stroke weights for borders and rings.
enum Stroke {
    static let hairline: CGFloat = 0.5
    static let regular: CGFloat = 1
    /// Focus rings and selected states — the guideline's 2px `#FF6900` ring.
    static let emphasis: CGFloat = 2
}

/// Shadows. Light mode leans on shadow for depth; dark mode leans on elevated
/// surface color, because a black shadow on a near-black background is invisible
/// and only serves to muddy the edge.
enum Elevation {
    /// Resting cards.
    static func card(_ scheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(scheme == .dark ? 0.24 : 0.07), 12, 2)
    }

    /// Floating surfaces: sheets, popovers, menus, HUDs.
    static func floating(_ scheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(scheme == .dark ? 0.34 : 0.14), 24, 8)
    }

    /// A brand-tinted glow. Reserved for the primary action and live states —
    /// on an ordinary card it turns the whole screen orange, which is how the
    /// previous build ended up bloomed.
    static func brandGlow(_ intensity: Double = 0.30) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (AppColors.brand.opacity(intensity), 18, 6)
    }
}

/// Reading measure and pane sizing.
///
/// A line of text stops being readable past roughly 75 characters; on a 3456pt
/// Mac window an un-capped composer or paragraph spans the whole display, which
/// is the single most "this is a phone app" tell in the current Mac build.
enum Measure {
    /// Max width for running prose and the composer.
    static let text: CGFloat = 720
    /// Max width for a content column that includes cards and controls.
    static let content: CGFloat = 960
    /// Max width for a wide dashboard/grid surface.
    static let wide: CGFloat = 1280

    /// Minimum comfortable hit target. 44pt on iOS (HIG), 28pt on Mac where
    /// the pointer is precise and 44pt rows read as a phone list.
    #if os(macOS)
    static let hitTarget: CGFloat = 28
    #else
    static let hitTarget: CGFloat = 44
    #endif
}

extension View {
    /// Constrain to a reading measure and center it. The Mac fix, applied once.
    func measured(_ width: CGFloat = Measure.content) -> some View {
        frame(maxWidth: width, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Standard card surface: elevated fill, concentric radius, scheme-aware shadow.
    func cardSurface(radius: CGFloat = Radius.lg) -> some View {
        modifier(CardSurfaceModifier(radius: radius))
    }
}

private struct CardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shadow = Elevation.card(scheme)
        return content
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: Hairline.width)
            )
            .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}
