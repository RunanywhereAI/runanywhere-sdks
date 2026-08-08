//
//  AdaptiveLayout.swift
//  RunAnywhereAI
//
//  Cross-platform adaptive layout helpers for iOS, iPadOS, and macOS
//

import SwiftUI

// MARK: - Platform Detection

/// Enum representing the current device form factor
enum DeviceFormFactor {
    case phone
    case tablet
    case desktop

    static var current: DeviceFormFactor {
        #if os(macOS)
        return .desktop
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .tablet
        }
        return .phone
        #endif
    }
}

// MARK: - Adaptive Sizing

/// Provides adaptive sizes that scale appropriately for different platforms
struct AdaptiveSizing {
    /// Share cards use one platform-invariant canvas so exported images retain
    /// identical geometry across share targets, while still respecting the
    /// current form factor's sheet width.
    static var shareCardWidth: CGFloat {
        min(AppLayout.shareCardWidth, sheetMaxWidth)
    }

    /// Microphone/main action button size
    static var micButtonSize: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 72
        case .tablet: return 80
        case .desktop: return 88
        }
    }

    /// Icon size inside the mic button
    static var micIconSize: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 28
        case .tablet: return 32
        case .desktop: return 36
        }
    }

    /// Conversation area max width
    static var conversationMaxWidth: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return .infinity
        case .tablet: return 800
        case .desktop: return 900
        }
    }

    /// Horizontal padding for main content
    static var contentPadding: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 16
        case .tablet: return 24
        case .desktop: return 32
        }
    }

    /// Toolbar button minimum hit target
    static var toolbarButtonSize: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 44
        case .tablet: return 44
        case .desktop: return 36
        }
    }

    /// Audio level bar width
    static var audioBarWidth: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 25
        case .tablet: return 30
        case .desktop: return 35
        }
    }

    /// Audio level bar height
    static var audioBarHeight: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 8
        case .tablet: return 10
        case .desktop: return 12
        }
    }

    /// Modal/sheet minimum width
    static var sheetMinWidth: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 320
        case .tablet: return 500
        case .desktop: return 550
        }
    }

    /// Modal/sheet ideal width
    static var sheetIdealWidth: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 375
        case .tablet: return 600
        case .desktop: return 700
        }
    }

    /// Modal/sheet max width
    static var sheetMaxWidth: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 428
        case .tablet: return 700
        case .desktop: return 850
        }
    }

    /// Modal/sheet minimum height
    static var sheetMinHeight: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 400
        case .tablet: return 500
        case .desktop: return 550
        }
    }

    /// Modal/sheet ideal height
    static var sheetIdealHeight: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 600
        case .tablet: return 650
        case .desktop: return 700
        }
    }

    /// Modal/sheet max height
    static var sheetMaxHeight: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 800
        case .tablet: return 800
        case .desktop: return 850
        }
    }

    /// Model badge font size
    static var badgeFontSize: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 9
        case .tablet: return 10
        case .desktop: return 11
        }
    }

    /// Badge horizontal padding
    static var badgePaddingH: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 8
        case .tablet: return 10
        case .desktop: return 12
        }
    }

    /// Badge vertical padding
    static var badgePaddingV: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 4
        case .tablet: return 5
        case .desktop: return 6
        }
    }
}

// MARK: - Adaptive Modal/Sheet Wrapper
struct AdaptiveSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                AdaptiveSheetChrome(isPresented: $isPresented) {
                    self.sheetContent()
                }
                    .frame(
                        minWidth: AdaptiveSizing.sheetMinWidth,
                        idealWidth: AdaptiveSizing.sheetIdealWidth,
                        maxWidth: AdaptiveSizing.sheetMaxWidth,
                        minHeight: AdaptiveSizing.sheetMinHeight,
                        idealHeight: AdaptiveSizing.sheetIdealHeight,
                        maxHeight: AdaptiveSizing.sheetMaxHeight
                    )
            }
        #else
        content
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                self.sheetContent()
            }
        #endif
    }
}

/// Adds a consistent, discoverable close affordance to macOS sheet content.
/// SwiftUI sheets do not reliably expose the hosting window's close button when
/// the presented view supplies its own content chrome, so keep the affordance in
/// the shared sheet wrapper instead of duplicating it in every feature view.
#if os(macOS)
private struct AdaptiveSheetChrome<Content: View>: View {
    @Binding var isPresented: Bool
    let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            content()
        }
    }
}
#endif

// MARK: - View Extensions
extension View {
    func adaptiveSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(AdaptiveSheet(
            isPresented: isPresented,
            onDismiss: onDismiss,
            sheetContent: content
        ))
    }
}

// MARK: - Adaptive Mic Button

/// A reusable microphone/action button that scales appropriately for all platforms
struct AdaptiveMicButton: View {
    let isActive: Bool
    let isPulsing: Bool
    let isLoading: Bool
    let activeColor: Color
    let inactiveColor: Color
    let icon: String
    let action: () -> Void
    let onLongPress: (() -> Void)?

    init(
        isActive: Bool = false,
        isPulsing: Bool = false,
        isLoading: Bool = false,
        activeColor: Color = .red,
        inactiveColor: Color = AppColors.primaryAccent,
        icon: String = "mic.fill",
        action: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil
    ) {
        self.isActive = isActive
        self.isPulsing = isPulsing
        self.isLoading = isLoading
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.icon = icon
        self.action = action
        self.onLongPress = onLongPress
    }

    private var micContent: some View {
        ZStack {
            // The halo sits behind the button, so a capture state reads at a
            // glance from across a desk without the icon ever being obscured.
            if isPulsing {
                MicCaptureHalo(diameter: AdaptiveSizing.micButtonSize)
            }

            Circle()
                .fill(isActive ? activeColor : inactiveColor)
                .frame(width: AdaptiveSizing.micButtonSize, height: AdaptiveSizing.micButtonSize)

            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            } else {
                Image(systemName: icon)
                    .font(.system(size: AdaptiveSizing.micIconSize))
                    .foregroundColor(.white)
                    .contentTransition(.symbolEffect(.replace))
                    // Icon swap is a micro-interaction, and it now routes
                    // through the token path so Reduce Motion is handled.
                    .motionAware(Motion.microFade, value: icon)
            }
        }
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                micButton
                    .glassEffect(.regular.interactive())
            } else {
                micButton
            }
        }
    }

    // A real Button hit-tests reliably under `.glassEffect(.interactive())`;
    // a bare `.onTapGesture` gets swallowed by the interactive glass layer,
    // which made the mic untappable on iOS 26.
    private var micButton: some View {
        Button(action: action) {
            micContent
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress?() ?? action() }
        )
        .accessibilityLabel("Microphone")
        .accessibilityHint(
            onLongPress != nil
                ? "Double tap to toggle recording. Long press for alternate action."
                : "Double tap to toggle recording."
        )
        .accessibilityAction(named: "Long Press") { onLongPress?() ?? action() }
    }
}

// MARK: - Mic Capture Halo

/// The "capture is live" ring behind the mic button.
///
/// This has an informational job — it is the difference between a mic that is
/// armed and a mic that is merely tinted — so unlike a decorative pulse it is
/// allowed to repeat. What it is not allowed to do is drift: the previous
/// version set `scaleEffect(1.3)` and `opacity(0)` as *constants* and then
/// attached a `repeatForever`, so the ring was permanently invisible and
/// animated nothing at all. It was a pulse that had never once pulsed.
///
/// Driven by a clock rather than a toggled `@State` so two mics on screen stay
/// in phase and a re-render mid-cycle cannot restart the curve. Suppressed
/// entirely under Reduce Motion, where the static ring still marks the state.
private struct MicCaptureHalo: View {
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// One expansion per 1.6s — the canonical ambient breathe.
    private static let period: Double = 1.6

    var body: some View {
        if reduceMotion {
            ring(scale: 1.18, opacity: 0.5)
        } else {
            TimelineView(.animation) { context in
                let phase = Self.phase(at: context.date)
                // Expand outward and fade as it goes: the ring reads as
                // something *leaving* the mic, which is the direction sound
                // travels. Fading to zero at the outer edge means no hard pop
                // when the cycle restarts at the center.
                ring(scale: 1.0 + 0.30 * phase, opacity: 0.55 * (1 - phase))
            }
        }
    }

    private func ring(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(Color.white.opacity(opacity), lineWidth: Stroke.regular)
            .frame(width: diameter, height: diameter)
            .scaleEffect(scale)
            // Transform and opacity only — no layout pass per frame.
            .allowsHitTesting(false)
    }

    private static func phase(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return CGFloat(elapsed / period)
    }
}

// MARK: - Adaptive Audio Level Indicator

/// A real level meter, on the shared audio figure.
///
/// The previous implementation lit `index < Int(level * barCount)` bars fully
/// green and left the rest grey — a segmented battery gauge, which at 10 bars
/// quantises a continuous microphone level into 10 visible steps and jitters
/// between two of them at a steady speaking volume.
///
/// It now delegates to `AudioActivityBars.level`, so the three voice screens
/// that show audio all show the *same* figure with the same silhouette, spacing,
/// and motion signature, and the meter is a genuine readout of the signal.
struct AdaptiveAudioLevelIndicator: View {
    /// Current input level, 0...1.
    let level: Float
    let barCount: Int

    init(level: Float, barCount: Int = 10) {
        self.level = level
        self.barCount = barCount
    }

    var body: some View {
        AudioActivityBars(
            mode: .level(level),
            tint: AppColors.statusGreen,
            barCount: barCount,
            height: AdaptiveSizing.audioBarHeight
        )
    }
}

// MARK: - Adaptive Sheet Frame Modifier

/// Applies appropriate frame constraints for sheets on macOS
struct AdaptiveSheetFrameModifier: ViewModifier {
    var minWidth: CGFloat?
    var idealWidth: CGFloat?
    var maxWidth: CGFloat?
    var minHeight: CGFloat?
    var idealHeight: CGFloat?
    var maxHeight: CGFloat?

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(
                minWidth: minWidth ?? AdaptiveSizing.sheetMinWidth,
                idealWidth: idealWidth ?? AdaptiveSizing.sheetIdealWidth,
                maxWidth: maxWidth ?? AdaptiveSizing.sheetMaxWidth,
                minHeight: minHeight ?? AdaptiveSizing.sheetMinHeight,
                idealHeight: idealHeight ?? AdaptiveSizing.sheetIdealHeight,
                maxHeight: maxHeight ?? AdaptiveSizing.sheetMaxHeight
            )
        #else
        content
        #endif
    }
}

// MARK: - Additional View Extensions

extension View {
    /// Applies adaptive sheet frame constraints (macOS only)
    func adaptiveSheetFrame(
        minWidth: CGFloat? = nil,
        idealWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        idealHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil
    ) -> some View {
        modifier(AdaptiveSheetFrameModifier(
            minWidth: minWidth,
            idealWidth: idealWidth,
            maxWidth: maxWidth,
            minHeight: minHeight,
            idealHeight: idealHeight,
            maxHeight: maxHeight
        ))
    }

    /// Constrains to conversation area width
    func adaptiveConversationWidth() -> some View {
        frame(maxWidth: AdaptiveSizing.conversationMaxWidth, alignment: .leading)
    }
}
