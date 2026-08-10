//
//  Surface.swift
//  RunAnywhereAI
//
//  One shim for every floating surface in the app.
//
//  Liquid Glass (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`,
//  `ToolbarSpacer`, `.backgroundExtensionEffect`) is iOS 26 / macOS 26 and does
//  **not** back-deploy. The app's floor is iOS 17.5 / macOS 14.5, so every call
//  site would otherwise need its own `if #available` ladder — which is how the
//  previous build ended up with zero modern materials anywhere: the ladder was
//  too expensive to write 40 times, so nobody wrote it once.
//
//  Written once, here. Views ask for a *depth level*, not an API.
//

import SwiftUI

/// How far a surface floats above the content behind it.
enum RASurfaceLevel {
    /// Window and screen chrome: top bars, bottom bars, sidebars. Sits flush
    /// against content and lets it show through.
    case chrome
    /// The composer, HUDs, popovers, toasts. Reads as a separate object.
    case floating
    /// A small control's own background: chips, icon buttons, pills.
    case control
}

extension View {
    /// Applies the platform's best available material for `level`, clipped to a
    /// continuous rounded rectangle. Pass `Radius.pill` for a capsule.
    func raSurface(_ level: RASurfaceLevel, radius: CGFloat = Radius.lg) -> some View {
        modifier(RASurfaceModifier(level: level, radius: radius))
    }
}

private struct RASurfaceModifier: ViewModifier {
    @Environment(\.colorScheme)
    private var scheme

    let level: RASurfaceLevel
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .modifier(SurfaceShadow(level: level, scheme: scheme))
        } else {
            content
                .background(fallbackMaterial, in: shape)
                .overlay(
                    shape.strokeBorder(borderColor, lineWidth: Hairline.width)
                )
                .modifier(SurfaceShadow(level: level, scheme: scheme))
        }
    }

    private var fallbackMaterial: Material {
        switch level {
        case .chrome: return .bar
        case .floating: return .regularMaterial
        case .control: return .thinMaterial
        }
    }

    private var borderColor: Color {
        switch level {
        case .chrome, .control: return AppColors.borderSubtle
        case .floating: return AppColors.border
        }
    }
}

/// Only `.floating` casts a shadow. Chrome that shadows reads as a floating
/// card wedged into the window; a control that shadows blooms a whole toolbar.
private struct SurfaceShadow: ViewModifier {
    let level: RASurfaceLevel
    let scheme: ColorScheme

    func body(content: Content) -> some View {
        switch level {
        case .floating:
            let shadow = Elevation.floating(scheme)
            return AnyView(content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y))
        case .chrome, .control:
            return AnyView(content)
        }
    }
}

// MARK: - Brand button

/// The primary action. `.buttonStyle(.glassProminent)` is 26-only, so this is
/// the one place the tier split for buttons lives.
struct RAProminentButtonStyle: ButtonStyle {
    var radius: CGFloat = Radius.sm

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .appType(.cardTitle)
            // Ink, not white. `AppColors.onBrandLarge` is white and its own doc comment
            // restricts it to "large or bold text only" — but white on #FF6900 is 2.89:1,
            // which is under AA's 4.5:1 AND under the 3:1 large-text floor, so no size
            // rescues it on a SOLID fill. (`.cardTitle` is 17pt semibold on iOS and only
            // 13pt on the Mac, which is not large by any measure.) `onBrand` is the
            // measured pair at ~6.1:1, and it is the same ink the web `.btn-primary` and
            // Android's `onPrimary` token now carry, so the primary action reads
            // identically on all four surfaces. `onBrandLarge` stays for the *gradient*
            // brand moment, where the red stop reaches 3.8:1 and §5 documents the
            // deviation — the user's chat bubble.
            .foregroundStyle(AppColors.onBrand)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .background(AppColors.brand, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            // `motionAware` and not a bare `.animation`: the press response is
            // travel, and travel is what Reduce Motion asks us to drop.
            .motionAware(Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RAProminentButtonStyle {
    static var raProminent: RAProminentButtonStyle { RAProminentButtonStyle() }
}
