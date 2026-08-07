//
//  AppColors.swift
//  RunAnywhereAI
//
//  RunAnywhere Brand Color Palette
//  Color scheme matching RunAnywhere.ai website
//  Primary accent: RunAnywhere brand orange (#FF6900) - the logo primary
//  Brand tokens mirror examples/DESIGN_GUIDELINE.md (canonical source)
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

// MARK: - Dynamic color helper

extension Color {
    /// A color that resolves itself against the OS appearance — light/dark, and
    /// optionally Increase Contrast.
    ///
    /// The previous palette shipped `…Light` and `…Dark` as *separate static
    /// constants*, which meant every call site had to read the color scheme and
    /// pick — so in practice almost none did, and the app rendered its dark
    /// values in light mode. A semantic token has to carry both values itself;
    /// that is the whole job of a semantic token.
    ///
    /// The high-contrast arguments default to `nil` and fall back to the base
    /// pair, so a token only carries them where a contrast ratio was actually
    /// measured as failing.
    static func dynamic(
        light: UInt,
        dark: UInt,
        lightHighContrast: UInt? = nil,
        darkHighContrast: UInt? = nil
    ) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let boost = traits.accessibilityContrast == .high
            let hex: UInt = switch (isDark, boost) {
            case (true, true): darkHighContrast ?? dark
            case (true, false): dark
            case (false, true): lightHighContrast ?? light
            case (false, false): light
            }
            return UIColor(Color(hex: hex))
        })
        #else
        return Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let boost = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let hex: UInt = switch (isDark, boost) {
            case (true, true): darkHighContrast ?? dark
            case (true, false): dark
            case (false, true): lightHighContrast ?? light
            case (false, false): light
            }
            return NSColor(Color(hex: hex))
        })
        #endif
    }
}

// MARK: - App Colors (RunAnywhere Brand Theme)
struct AppColors {
    // ====================
    // SEMANTIC TOKENS — the canonical set (examples/DESIGN_GUIDELINE.md §2)
    // ====================
    // These carry BOTH light and dark values in one token, so a call site can
    // never render the wrong scheme's value. Prefer these over everything below;
    // the flat constants that follow are retained only until their call sites
    // are migrated.

    // --- Surface ladder ---------------------------------------------------
    // Three rungs, and the two schemes move in OPPOSITE directions: light mode
    // lifts off paper toward white, dark mode lifts off ink toward grey. Light
    // mode can lift at all only because the brand background is *paper*
    // (`#FBFAF8`), not white — that is what leaves white available as the rung
    // above it.
    //
    // Because nothing is brighter than white, light mode has no fourth rung.
    // So depth above `surface` is carried by SHADOW (`Elevation.floating`) and
    // nesting *inside* a card goes DOWN to `surfaceSunken` rather than up.
    //
    // Two rungs holding the same value is the failure to avoid: the reference
    // app shipped that collision twice — an invisible quote block, then a whole
    // panel that never rendered. When editing these, check both schemes; the
    // bug is invisible in the one you happen to be running.

    /// Page background. Paper in light, brand ink in dark.
    static let background = Color.dynamic(light: 0xFBFAF8, dark: 0x0C0E17)
    /// Cards and rows sitting on `background`.
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x131620)
    /// Recessed fill — input wells, code blocks, track backgrounds, and any
    /// surface nested inside a `surface` card.
    static let surfaceSunken = Color.dynamic(light: 0xF3F4F6, dark: 0x0F131C)
    /// Floating chrome: sheets, popovers, menus, HUDs.
    ///
    /// Identical to `surface` in light mode on purpose — white is the top of the
    /// light ladder, so a popover is separated from the card below it by its
    /// shadow, not by its fill. Dark mode has room to lift, and does.
    static let surfaceFloating = Color.dynamic(light: 0xFFFFFF, dark: 0x1B2231)

    /// Primary text. 15.8:1 on `background` light, 16.4:1 dark.
    static let foreground = Color.dynamic(light: 0x10182B, dark: 0xF7F4EE)
    /// Secondary text. 4.8:1 on `background` light, 6.9:1 dark — clears AA for
    /// body text in both. High contrast pushes both past AAA 7:1.
    static let mutedForeground = Color.dynamic(
        light: 0x6B7280, dark: 0x9AA1B3,
        lightHighContrast: 0x4B5563, darkHighContrast: 0xC3C9D6
    )
    /// Muted/secondary fill.
    static let muted = Color.dynamic(light: 0xF3F4F6, dark: 0x1C2230)

    // Borders carry no WCAG reference, so high contrast deepens them rather
    // than chasing a ratio: a 1px 1.2:1 seam is legible to someone looking for
    // it and invisible to everyone else.
    /// Standard border / input outline.
    static let border = Color.dynamic(
        light: 0xE5E7EB, dark: 0x242A38,
        lightHighContrast: 0xB6BCC6, darkHighContrast: 0x49525F
    )
    /// A border that should read as a seam rather than an edge.
    static let borderSubtle = Color.dynamic(
        light: 0xECEEF1, dark: 0x1E2532,
        lightHighContrast: 0xC4CAD3, darkHighContrast: 0x3C4552
    )

    // --- Brand ------------------------------------------------------------
    // `#FF6900` needs three tokens, not one. The guideline forbids darkening
    // the hue for *fills* — and it is still true that as a 2pt line or a link
    // on paper the flat brand value measures ≈2.9:1 against `background` and
    // cannot be read. So: `brand` for fills (exact brand value, never altered),
    // `brandInk` for anything thin the eye must resolve as a shape — text,
    // links, 1–2pt strokes, chart lines. Dark mode needs no adjustment; the
    // orange already reads at 6.6:1 on ink.

    /// The brand value, exact. Fills, the mark, gradient start.
    static let brand = Color(hex: 0xFF6900)
    /// Brand-as-foreground: links, thin strokes, chart lines, tinted glyphs.
    /// Light is deepened to 4.6:1 on `background`; dark is the brand value.
    static let brandInk = Color.dynamic(
        light: 0xB84400, dark: 0xFF8534,
        lightHighContrast: 0x8F3400, darkHighContrast: 0xFFA366
    )
    /// Brand gradient end (the logo's red stop).
    static let gradientEnd = Color(hex: 0xFB2C36)
    /// The brand gradient — the mark, hero CTAs, brand moments.
    static let brandGradient = LinearGradient(
        colors: [brand, gradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Text placed ON a solid brand fill.
    ///
    /// White on `#FF6900` is ≈2.9:1 and FAILS WCAG AA (guideline §5). It is
    /// accepted for large/bold brand moments only. Ink on orange is ≈6.1:1 and
    /// is what small text must use — so this token is ink, and the large-CTA
    /// exception opts in explicitly via `onBrandLarge`.
    static let onBrand = Color(hex: 0x10182B)
    /// White-on-orange, permitted for large or bold text only.
    static let onBrandLarge = Color.white

    // --- Status -----------------------------------------------------------
    // The guideline's §2 values, exactly. Meanings are RESERVED so a reader can
    // trust the color on sight: `success` = loaded and ready; `warning` =
    // degraded but usable; `danger` = failure and destructive actions ONLY;
    // `info` = neutral notice. A download in progress is `brand`, never `info` —
    // progress is not information.
    //
    // These are fills and glyphs. As *small text* on `background` the light
    // values measure 3.1:1 (success) / 2.2:1 (warning) / 3.8:1 (danger) /
    // 3.3:1 (info) and none clears AA, so the `…Text` variants below exist for
    // when the status has to be a word rather than a dot.
    static let success = Color.dynamic(light: 0x269B57, dark: 0x45C97F)
    static let warning = Color.dynamic(light: 0xF59E0B, dark: 0xF7AE2A)
    static let danger = Color.dynamic(light: 0xEF4444, dark: 0xDC2626)
    static let info = Color.dynamic(light: 0x3B82F6, dark: 0x60A5FA)

    /// Status colors deepened to clear AA as small text on `background`
    /// (4.6–5.4:1 light). The dark values already clear it, so they stand.
    /// Use for status *words*; use the plain tokens above for dots and fills.
    static let successText = Color.dynamic(light: 0x1B7442, dark: 0x45C97F)
    static let warningText = Color.dynamic(light: 0x8A5A06, dark: 0xF7AE2A)
    static let dangerText = Color.dynamic(light: 0xC4262A, dark: 0xF06A6A)
    static let infoText = Color.dynamic(light: 0x1D4FD8, dark: 0x60A5FA)

    /// Theme-invariant code surface (guideline §2).
    static let codeSurface = Color(hex: 0x021A28)
    static let codeForeground = Color(hex: 0xD3DCE8)

    // ====================
    // PRIMARY ACCENT COLORS - RunAnywhere Brand Colors
    // ====================
    // Primary brand color - vibrant orange/red from RunAnywhere.ai website
    static let primaryAccent = Color(hex: 0xFF6900)  // RunAnywhere brand orange - the logo primary
    static let primaryOrange = Color(hex: 0xFF6900)  // Same as primary accent
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
    static let userBubbleGradientEnd = Color(hex: 0xE65E00)    // Slightly darker brand orange
    static let messageBubbleUser = primaryAccent               // Vibrant orange-red

    // Assistant bubbles - clean gray (uses system colors for dark mode adaptation)
    static let assistantBubbleBg = backgroundGray5
    static let messageBubbleAssistant = backgroundGray5
    static let messageBubbleAssistantGradientStart = backgroundGray5
    static let messageBubbleAssistantGradientEnd = backgroundGray6

    // Dark mode - toned down variant for reduced eye strain in low-light
    static let messageBubbleUserDark = Color(hex: 0xCC5400)    // Darker brand orange (80% brightness)
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

    // Branded benchmark share card. These colors stay platform-invariant because
    // the same view is rasterized for social sharing on iOS and macOS.
    static let shareCardBackgroundTop = Color(hex: 0x1A0E06)
    static let shareCardBackgroundBottom = Color(hex: 0x0B0B0C)
    static let shareCardAccent = primaryAccent
    static let shareCardTextPrimary = Color(hex: 0xF5F3F1)
    static let shareCardTextSecondary = Color(hex: 0x9A938E)
    static let shareCardRowBackground = Color.white.opacity(0.08)

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
