//
//  EmptyStateMark.swift
//  RunAnywhereAI
//
//  The app's empty-state figure: one composed illustrative mark instead of a
//  lone SF Symbol floating in the middle of a screen.
//
//  Why this exists. An empty state is the *first* thing a reader sees on a
//  surface, and `ContentUnavailableView`'s bare 48pt glyph reads as an error
//  even when nothing is wrong. But hand-drawing seven illustrations means seven
//  stroke weights and seven silhouettes. So the figure is *composed*: a brand
//  aperture ring, a soft brand bloom, and the modality's own SF Symbol at the
//  center — same geometry every time, only the glyph changes. Every screen's
//  empty state is recognisably the same object, which is what makes it read as a
//  designed state rather than a missing one.
//
//  Motion. The bloom breathes on the canonical 1.6s linear ambient period and
//  the ring sweeps on the 1.2s shimmer period — both suppressed entirely under
//  Reduce Motion (per DESIGN_GUIDELINE §6.5: a `repeatForever` collapsed to a
//  short fade still repeats forever). Nothing here animates on a timer the
//  reader has to wait for; the figure is fully legible on the first frame.
//

import SwiftUI

/// A composed illustrative mark for empty states and first-run surfaces.
struct EmptyStateMark: View {
    /// The modality glyph at the center. One glyph, one meaning, app-wide.
    let systemImage: String
    /// The accent this surface is themed with. Defaults to the brand.
    var tint: Color = AppColors.brand
    /// Overall diameter. 132 is the hero size; 88 fits inside a card.
    var diameter: CGFloat = 132

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var breathing = false
    @State private var sweep = false

    /// The glyph is 34% of the figure so the ring always reads as an aperture
    /// around it rather than a tight collar.
    private var glyphSize: CGFloat { diameter * 0.34 }

    var body: some View {
        ZStack {
            bloom
            aperture
            glyph
        }
        .frame(width: diameter, height: diameter)
        // Decoration: the caller's title and message already say what this is,
        // and a screen reader announcing "waveform image" adds nothing.
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            breathing = true
            sweep = true
        }
        .onChange(of: reduceMotion) { _, isReduced in
            // Honour the setting changing while the view is on screen, rather
            // than only at first appearance.
            breathing = !isReduced
            sweep = !isReduced
        }
    }

    /// The soft brand light behind everything. Blur scales with the figure so an
    /// 88pt mark is not wearing a 132pt mark's halo.
    private var bloom: some View {
        Circle()
            .fill(tint.opacity(0.22))
            .blur(radius: diameter * 0.18)
            .scaleEffect(breathing ? 1.06 : 0.94)
            .animation(Motion.resolveAmbient(reduceMotion: reduceMotion), value: breathing)
    }

    /// Two rings. The full one is structure; the trimmed arc rotating over it is
    /// the only thing that says "listening for something" rather than "broken".
    private var aperture: some View {
        ZStack {
            Circle()
                .strokeBorder(tint.opacity(0.20), lineWidth: Stroke.emphasis)

            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(
                    tint.opacity(0.85),
                    style: StrokeStyle(lineWidth: Stroke.emphasis, lineCap: .round)
                )
                .rotationEffect(.degrees(sweep ? 360 : 0))
                .animation(
                    Motion.resolveAmbient(Motion.shimmer, reduceMotion: reduceMotion),
                    value: sweep
                )
        }
        .padding(diameter * 0.06)
    }

    /// The glyph sits on its own material disc, so it stays legible against a
    /// photo, a gradient, or a plain background without needing a scrim.
    private var glyph: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: glyphSize, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: diameter * 0.62, height: diameter * 0.62)
            .background(.ultraThinMaterial, in: Circle())
    }
}

// MARK: - Full empty state

/// Title, message, and one action beneath the mark.
///
/// A deliberate replacement for `ContentUnavailableView` on branded surfaces:
/// same three-part structure, but it carries the app's mark, type roles, and
/// motion. `ContentUnavailableView` stays the right answer for plain search
/// results, where matching the system exactly is the point.
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    var tint: Color = AppColors.brand
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Space.lg) {
            EmptyStateMark(systemImage: systemImage, tint: tint)
                .padding(.bottom, Space.xs)

            VStack(spacing: Space.sm) {
                Text(title)
                    .appType(.title)
                    .multilineTextAlignment(.center)

                Text(message)
                    .appType(.secondary)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    // The reading measure, not the container: centered prose
                    // running the full width of a 1200pt Mac window is a wall.
                    .frame(maxWidth: 420)
            }

            actions()
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    /// An empty state with nothing to do — rare, and usually a sign the surface
    /// should offer something.
    init(systemImage: String, title: String, message: String, tint: Color = AppColors.brand) {
        self.init(systemImage: systemImage, title: title, message: message, tint: tint) { EmptyView() }
    }
}

#Preview("Mark sizes") {
    HStack(spacing: Space.xl) {
        EmptyStateMark(systemImage: "waveform", diameter: 132)
        EmptyStateMark(systemImage: "doc.text.magnifyingglass", tint: AppColors.primaryBlue, diameter: 88)
        EmptyStateMark(systemImage: "sparkles", diameter: 64)
    }
    .padding(Space.xxl)
    .background(AppColors.background)
}

#Preview("Full state") {
    EmptyStateView(
        systemImage: "bubble.left.and.bubble.right",
        title: "No chats yet",
        message: "Pick a model and start a conversation. Everything runs on this device."
    ) {
        Button("Choose a model") {}
            .buttonStyle(.raProminent)
    }
    .background(AppColors.background)
}
