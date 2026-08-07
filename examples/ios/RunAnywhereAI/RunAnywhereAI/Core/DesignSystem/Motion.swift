//
//  Motion.swift
//  RunAnywhereAI
//
//  The app's motion language. Mirrors examples/DESIGN_GUIDELINE.md in spirit:
//  one place defines how this app moves, the way AppColors defines how it looks.
//
//  Rhythm tiers — micro 120ms / standard 240ms / emphasis 400ms / hero 700ms.
//  A duration outside these tiers is a bug, not a preference: four tiers is what
//  makes a hundred screens feel like one product rather than a hundred authors.
//
//  Every animated view MUST route through `motionAware(_:value:)` or
//  `Motion.resolve(_:reduceMotion:)`. Springs are motion sickness for some
//  readers; under Reduce Motion they collapse to a short crossfade that keeps
//  the state change legible without the travel.
//

import SwiftUI

enum Motion {
    // MARK: - Duration tiers (seconds)

    /// Tap feedback, chip selection, icon swaps. Below ~100ms reads as an
    /// instant jump; above ~150ms a tap starts to feel laggy.
    static let micro: Double = 0.12
    /// The default. Row inserts, disclosure, most state changes.
    static let standard: Double = 0.24
    /// Sheet content, hero swaps, anything crossing a large distance.
    static let emphasis: Double = 0.40
    /// Reserved for once-per-session brand moments (launch, first load).
    static let hero: Double = 0.70

    // MARK: - Springs

    /// Direct manipulation: the thing you just touched. Barely overshoots.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// The default spring for state that changes on its own.
    static let standardSpring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Large, soft travel — sheets and full-screen transitions.
    static let gentle = Animation.spring(response: 0.60, dampingFraction: 0.86)
    /// Deliberate overshoot. Success and arrival moments only; on a progress
    /// bar or a spinner a bounce reads as instability rather than delight.
    static let bouncy = Animation.spring(response: 0.38, dampingFraction: 0.66)

    // MARK: - Eases

    static let microFade = Animation.easeOut(duration: micro)
    static let standardFade = Animation.easeInOut(duration: standard)
    static let emphasisFade = Animation.easeInOut(duration: emphasis)

    // MARK: - Ambient motion
    //
    // Repeating decorative motion is exempt from the duration tiers and is
    // always `linear`: anything eased reads as a stutter when it loops, because
    // the slow ends stack up at the seam. Three canonical periods, and no
    // fourth — a breathe at 1.55s next to a breathe at 1.6s is just a bug that
    // is hard to see.

    /// Breathing / pulsing, 1.6s. Autoreverses: a breath has an out-breath.
    static let ambient = Animation.linear(duration: 1.6).repeatForever(autoreverses: true)

    /// Shimmer sweep, 1.2s. Does not autoreverse — a highlight travels one way
    /// and starts over; sliding it back is a different, wrong gesture.
    static let shimmer = Animation.linear(duration: 1.2).repeatForever(autoreverses: false)

    /// Indeterminate rotation, 1.0s per revolution. Never autoreverses.
    static let spinner = Animation.linear(duration: 1.0).repeatForever(autoreverses: false)

    // MARK: - Reduce Motion

    /// The crossfade every animation collapses to under Reduce Motion. Short
    /// enough not to feel like an animation, long enough that the change is
    /// perceived rather than blinked past.
    static let reducedFallback = Animation.easeInOut(duration: 0.15)

    /// The animation to actually use, given the reader's Reduce Motion setting.
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFallback : animation
    }

    /// Repeating decorative motion is suppressed entirely under Reduce Motion —
    /// collapsing an infinite loop to a short fade still loops forever.
    ///
    /// Pass the period you want; the default is the 1.6s breathe. Returning
    /// `nil` (rather than a very short animation) is what actually stops the
    /// loop when handed to `.animation(_:value:)`.
    static func resolveAmbient(_ animation: Animation = ambient, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - View integration

extension View {
    /// Animate `value` changes with automatic Reduce-Motion fallback.
    ///
    /// Prefer this over a bare `.animation(_:value:)` so the accessibility
    /// path can never be forgotten at a call site.
    func motionAware(_ animation: Animation = Motion.standardSpring, value: some Equatable) -> some View {
        modifier(MotionAwareModifier(animation: animation, value: value))
    }
}

private struct MotionAwareModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}

/// `withAnimation` that honors Reduce Motion.
///
/// Reads the setting from `UIAccessibility`/`NSWorkspace` rather than the
/// environment, because imperative call sites (button actions, event handlers)
/// have no `@Environment` to read from — which is exactly where the
/// accessibility path gets dropped in practice.
@MainActor
func withMotion<Result>(
    _ animation: Animation = Motion.standardSpring,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(Motion.resolve(animation, reduceMotion: Motion.systemReduceMotion), body)
}

extension Motion {
    /// The live system Reduce Motion setting, for imperative contexts.
    @MainActor
    static var systemReduceMotion: Bool {
        #if os(iOS)
        UIAccessibility.isReduceMotionEnabled
        #elseif os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        false
        #endif
    }
}
