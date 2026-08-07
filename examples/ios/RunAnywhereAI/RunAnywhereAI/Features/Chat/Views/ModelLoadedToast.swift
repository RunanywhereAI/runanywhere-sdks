//
//  ModelLoadedToast.swift
//  RunAnywhereAI
//
//  "Model Ready" — the arrival moment after a load finishes.
//
//  This is one of the very few places in the app licensed to use
//  `Motion.bouncy`: the guideline restricts overshoot to genuine arrival, and a
//  model becoming usable after a multi-second load is exactly that. Everything
//  else here is deliberately quiet, because a toast that celebrates too hard is
//  a toast the reader starts dismissing without reading.
//
//  The checkmark draws itself on (`.symbolEffect(.drawOn)`, iOS 18+) rather than
//  fading in. A checkmark that fades is a static image; one that draws is the
//  system reporting a result, and it is the difference between "there is a green
//  tick here" and "it just finished".
//

import SwiftUI

struct ModelLoadedToast: View {
    let modelName: String
    @Binding var isShowing: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if isShowing {
                card
                    .padding(.horizontal, Space.lg)
                    .padding(.top, Space.sm)
                    // Enters from the top edge it is pinned to, so the travel
                    // reads as "arrived from off-screen" rather than "appeared".
                    // Scale is asymmetric: it settles in with the overshoot, and
                    // leaves by simply fading, because nobody watches a toast go.
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            Spacer(minLength: 0)
        }
        .motionAware(Motion.bouncy, value: isShowing)
    }

    private var card: some View {
        HStack(spacing: Space.md) {
            checkmark

            VStack(alignment: .leading, spacing: 1) {
                Text("Model ready")
                    .appType(.chip)
                    .foregroundStyle(AppColors.textPrimary)

                Text(modelName)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        // `.floating` is the level that reads as a separate plane above the
        // transcript, and it carries `Elevation.floating` itself — no local
        // `.shadow` here, or the toast gets two.
        .raSurface(.floating, radius: Radius.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Model ready: \(modelName)")
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(AppColors.statusGreen)
            .modifier(DrawOnEffect(isActive: isShowing && !reduceMotion))
    }
}

/// `.symbolEffect(.drawOn)` is iOS 26 / macOS 26; the app floor is 17.5 / 14.5.
/// Below that the fallback is `.bounce`, which has been available since 17 and
/// carries the same "this just happened" reading with less craft. Reduce Motion
/// gets the plain static symbol, which is why `isActive` gates both.
private struct DrawOnEffect: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.symbolEffect(.drawOn, isActive: isActive)
        } else {
            content.symbolEffect(.bounce, value: isActive)
        }
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let modelName: String
    let duration: TimeInterval

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                // An overlay, not a `ZStack` wrapper: wrapping the whole screen
                // in a `ZStack` re-parents the content and drops the safe-area
                // and toolbar behaviour the chat depends on.
                ModelLoadedToast(modelName: modelName, isShowing: $isShowing)
                    .allowsHitTesting(false)
            }
            .onChange(of: isShowing) { _, newValue in
                guard newValue else { return }
                Haptics.success()
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(duration))
                    // Re-check: a second load may have re-shown it, and a load
                    // that finished 200ms ago should not be dismissed by the
                    // previous one's timer.
                    guard isShowing else { return }
                    withMotion(Motion.standardFade) { isShowing = false }
                }
            }
    }
}

extension View {
    func modelLoadedToast(isShowing: Binding<Bool>, modelName: String, duration: TimeInterval = 3.0) -> some View {
        modifier(ToastModifier(isShowing: isShowing, modelName: modelName, duration: duration))
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AppColors.background.ignoresSafeArea()

        ModelLoadedToast(
            modelName: "Qwen3 4B Instruct",
            isShowing: .constant(true)
        )
    }
}
