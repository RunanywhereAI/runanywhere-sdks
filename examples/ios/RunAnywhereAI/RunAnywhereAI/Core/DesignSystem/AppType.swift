//
//  AppType.swift
//  RunAnywhereAI
//
//  The app's type system: a table of semantic roles, not a list of point sizes.
//
//  This replaces `AppTypography`'s `system9 … system80`. That list named sizes
//  ("what") and left the meaning ("why") at the call site, so 96 views reached
//  past it to `.font(.system(size:weight:))` anyway and nothing kept a "card
//  title" on one screen the same size as a "card title" on another. A role
//  table inverts it: a view asks for `.cardTitle` and the table decides what
//  that means — so changing what a card title looks like is one edit here.
//
//  Mac runs its own smaller scale. It sits further from the eye and has no
//  user-facing text-size control, so scaling the phone's sizes down at render
//  time would be guesswork; each platform gets sizes drawn for it, per role.
//
//  SwiftUI scales `Font.system(size:)` with Dynamic Type automatically (unlike
//  UIKit's `UIFont.systemFont(ofSize:)`), so these sizes are a base to grow
//  from, not a fixed pixel count. `maxTypeSize` is where that growth stops.
//

import SwiftUI

enum AppType {
    /// What a piece of text *is*, semantically. Add a role rather than a size.
    enum Role: Hashable, CaseIterable {
        /// Big numeric readouts: a live timer, a benchmark's headline metric.
        case metric
        /// Screen-level title in a large-title navigation bar.
        case largeTitle
        /// A prominent screen or hero heading.
        case title
        /// Section heading inside a screen ("Models", "Recent").
        case sectionTitle
        /// Card and row titles, and button labels.
        case cardTitle
        /// Body copy: chat messages, descriptions, settings rows.
        case body
        /// Supporting copy under a title.
        case secondary
        /// Row metadata: sizes, dates, counts.
        case meta
        /// Timestamps and the smallest supporting text.
        case caption
        /// Uppercased group labels — tracked out.
        case overline
        /// Badge and chip labels.
        case chip
        /// Code, model IDs, file paths.
        case mono
        /// Numeric values that update live (tokens/sec, elapsed) — tabular so
        /// the readout doesn't twitch as digits change width.
        case monoMetric
    }

    private struct Style {
        /// Base point size on iOS.
        let ios: CGFloat
        /// Base point size on Mac — a genuinely redrawn scale, not iOS × k.
        let mac: CGFloat
        let weight: Font.Weight
        var design: Font.Design = .default
        /// Past this, growing the text costs more than it gains.
        var maxTypeSize: DynamicTypeSize = .accessibility5
        var monospacedDigits = false

        var size: CGFloat {
            #if os(macOS)
            mac
            #else
            ios
            #endif
        }
    }

    /// The one place a role's appearance is decided.
    ///
    /// A `switch` rather than a `[Role: Style]` dictionary so the compiler
    /// rejects an unhandled role outright — a lookup table would need a
    /// fallback, and a role silently rendering as body text is exactly the kind
    /// of drift this file exists to prevent.
    private static func style(for role: Role) -> Style {
        switch role {
        case .metric:
            // A 40pt readout at AX5 is wider than the screen, and a clipped
            // number is worse than a small one.
            Style(ios: 40, mac: 30, weight: .bold, maxTypeSize: .accessibility1, monospacedDigits: true)
        case .largeTitle:
            Style(ios: 34, mac: 24, weight: .bold)
        case .title:
            Style(ios: 28, mac: 20, weight: .bold)
        case .sectionTitle:
            Style(ios: 20, mac: 15, weight: .semibold)
        case .cardTitle:
            Style(ios: 17, mac: 13, weight: .semibold)
        case .body:
            Style(ios: 17, mac: 13, weight: .regular)
        case .secondary:
            Style(ios: 15, mac: 12, weight: .regular)
        case .meta:
            Style(ios: 13, mac: 11, weight: .regular)
        case .caption:
            Style(ios: 12, mac: 10, weight: .regular)
        case .overline:
            Style(ios: 12, mac: 10, weight: .semibold)
        case .chip:
            // Chips are badges, not prose. Let one scale to AX5 and
            // "Downloading" truncates to "Dow…", naming nothing, or wraps the
            // capsule into a circle. Surrounding titles still scale and
            // VoiceOver reads the label in full, so nothing is lost by holding
            // the badge steady.
            Style(ios: 12, mac: 11, weight: .semibold, maxTypeSize: .accessibility1)
        case .mono:
            Style(ios: 14, mac: 12, weight: .regular, design: .monospaced)
        case .monoMetric:
            Style(
                ios: 16,
                mac: 13,
                weight: .semibold,
                design: .monospaced,
                maxTypeSize: .accessibility2,
                monospacedDigits: true
            )
        }
    }

    /// The font for a role. Grows with Dynamic Type up to `maxTypeSize(role)`.
    static func font(_ role: Role) -> Font {
        let style = style(for: role)
        let font = Font.system(size: style.size, weight: style.weight, design: style.design)
        return style.monospacedDigits ? font.monospacedDigit() : font
    }

    /// The upper bound on Dynamic Type growth for a role.
    static func maxTypeSize(_ role: Role) -> DynamicTypeSize {
        style(for: role).maxTypeSize
    }

    /// Extra leading, on top of what the face carries.
    ///
    /// Only genuine paragraphs get any: a chip label or a timestamp is never
    /// more than a few words, and tighter leading reads as precision there
    /// rather than as cramping. At SF's default (~1.2×) a chat message at this
    /// app's reading measure sends the eye's return sweep hunting for the next
    /// line; 0.22× the point size lands the ratio near 1.4.
    static func lineSpacing(_ role: Role) -> CGFloat {
        switch role {
        case .body, .secondary:
            pointSize(role) * 0.22
        default:
            0
        }
    }

    /// Letter-spacing for uppercased labels. Capitals set solid read as one
    /// dark block; opened up by ~8% of their own size they read as a label.
    static func tracking(_ role: Role) -> CGFloat {
        switch role {
        case .overline:
            pointSize(role) * 0.08
        default:
            0
        }
    }

    /// The base point size a role renders at, for layout code that must reserve
    /// height. `Font` itself is opaque, so this is the only inspectable part.
    static func pointSize(_ role: Role) -> CGFloat { style(for: role).size }
}

extension View {
    /// Apply a type role: font, leading, tracking, and its Dynamic Type cap.
    func appType(_ role: AppType.Role) -> some View {
        font(AppType.font(role))
            .lineSpacing(AppType.lineSpacing(role))
            .tracking(AppType.tracking(role))
            .dynamicTypeSize(...AppType.maxTypeSize(role))
    }
}

extension Text {
    /// Apply a role to a `Text` that is about to be concatenated with `+`.
    ///
    /// Deliberately NOT an overload of `appType`: as an overload it would be the
    /// more specific match at every `Text(...).appType(...)` call site and would
    /// silently win, dropping the line-spacing and Dynamic Type cap everywhere.
    func appTypeRun(_ role: AppType.Role) -> Text {
        font(AppType.font(role))
    }
}
