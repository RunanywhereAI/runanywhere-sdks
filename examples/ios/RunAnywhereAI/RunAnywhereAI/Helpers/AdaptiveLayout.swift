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

    /// Secondary action button size
    static var actionButtonSize: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return 44
        case .tablet: return 50
        case .desktop: return 56
        }
    }

    /// Maximum content width for readable text
    static var maxContentWidth: CGFloat {
        switch DeviceFormFactor.current {
        case .phone: return .infinity
        case .tablet: return 700
        case .desktop: return 800
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
    let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .sheet(isPresented: $isPresented) {
                self.sheetContent()
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
            .sheet(isPresented: $isPresented) {
                self.sheetContent()
            }
        #endif
    }
}

// MARK: - Adaptive Form Style
struct AdaptiveFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .formStyle(.grouped)
            .scrollContentBackground(.visible)
        #else
        content
            .formStyle(.automatic)
        #endif
    }
}

// MARK: - Adaptive Navigation
struct AdaptiveNavigation<Content: View>: View {
    let title: String
    let content: () -> Content

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Custom title bar for macOS
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            content()
        }
        #else
        NavigationView {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
        #endif
    }
}

// MARK: - Adaptive Button Style
struct AdaptiveButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        if isPrimary {
            configuration.label
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primaryAccent)
                .controlSize(.regular)
        } else {
            configuration.label
                .buttonStyle(.bordered)
                .tint(AppColors.primaryAccent)
                .controlSize(.regular)
        }
        #else
        configuration.label
            .padding(.horizontal, isPrimary ? 16 : 12)
            .padding(.vertical, isPrimary ? 12 : 8)
            .background(isPrimary ? AppColors.primaryAccent : Color.secondary.opacity(0.2))
            .foregroundColor(isPrimary ? .white : .primary)
            .cornerRadius(8)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
        #endif
    }
}

// MARK: - View Extensions
extension View {
    func adaptiveSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(AdaptiveSheet(isPresented: isPresented, sheetContent: content))
    }

    func adaptiveFormStyle() -> some View {
        modifier(AdaptiveFormStyle())
    }

    func adaptiveButtonStyle(isPrimary: Bool = false) -> some View {
        buttonStyle(AdaptiveButtonStyle(isPrimary: isPrimary))
    }

    func adaptiveFrame() -> some View {
        #if os(macOS)
        self.frame(
            minWidth: 400,
            idealWidth: 600,
            maxWidth: 900,
            minHeight: 300,
            idealHeight: 500,
            maxHeight: 800
        )
        #else
        self
        #endif
    }

    func adaptiveToolbar<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        #if os(macOS)
        self.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                leading()
            }
            ToolbarItem(placement: .confirmationAction) {
                trailing()
            }
        }
        #else
        self.toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                leading()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                trailing()
            }
        }
        #endif
    }
}

// MARK: - Platform-Specific Colors
extension Color {
    static var adaptiveBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    static var adaptiveSecondaryBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }

    static var adaptiveTertiaryBackground: Color {
        #if os(macOS)
        Color(NSColor.textBackgroundColor)
        #else
        Color(.tertiarySystemBackground)
        #endif
    }

    static var adaptiveGroupedBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    static var adaptiveSeparator: Color {
        #if os(macOS)
        Color(NSColor.separatorColor)
        #else
        Color(.separator)
        #endif
    }

    static var adaptiveLabel: Color {
        #if os(macOS)
        Color(NSColor.labelColor)
        #else
        Color(.label)
        #endif
    }

    static var adaptiveSecondaryLabel: Color {
        #if os(macOS)
        Color(NSColor.secondaryLabelColor)
        #else
        Color(.secondaryLabel)
        #endif
    }
}

// MARK: - Adaptive Text Field
struct AdaptiveTextField: View {
    let title: String
    @Binding var text: String
    var isURL: Bool = false
    var isSecure: Bool = false
    var isNumeric: Bool = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
                    #if os(iOS)
                    .keyboardType(isURL ? .URL : (isNumeric ? .numberPad : .default))
                    .autocapitalization(isURL ? .none : .sentences)
                    #endif
            }
        }
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled(isURL)
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

    init(
        isActive: Bool = false,
        isPulsing: Bool = false,
        isLoading: Bool = false,
        activeColor: Color = .red,
        inactiveColor: Color = AppColors.primaryAccent,
        icon: String = "mic.fill",
        action: @escaping () -> Void
    ) {
        self.isActive = isActive
        self.isPulsing = isPulsing
        self.isLoading = isLoading
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                Button(action: action) {
                    ZStack {
                        // Background circle
                        Circle()
                            .fill(isActive ? activeColor : inactiveColor)
                            .frame(width: AdaptiveSizing.micButtonSize, height: AdaptiveSizing.micButtonSize)

                        // Pulsing effect when active
                        if isPulsing {
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                .frame(width: AdaptiveSizing.micButtonSize, height: AdaptiveSizing.micButtonSize)
                                .scaleEffect(1.3)
                                .opacity(0)
                                .animation(
                                    .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: isPulsing
                                )
                        }

                        // Icon or loading indicator
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: AdaptiveSizing.micIconSize))
                                .foregroundColor(.white)
                                .contentTransition(.symbolEffect(.replace))
                                .animation(.smooth(duration: 0.3), value: icon)
                        }
                    }
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive())
            } else {
                Button(action: action) {
                    ZStack {
                        // Background circle
                        Circle()
                            .fill(isActive ? activeColor : inactiveColor)
                            .frame(width: AdaptiveSizing.micButtonSize, height: AdaptiveSizing.micButtonSize)

                        // Pulsing effect when active
                        if isPulsing {
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                .frame(width: AdaptiveSizing.micButtonSize, height: AdaptiveSizing.micButtonSize)
                                .scaleEffect(1.3)
                                .opacity(0)
                                .animation(
                                    .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: isPulsing
                                )
                        }

                        // Icon or loading indicator
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: AdaptiveSizing.micIconSize))
                                .foregroundColor(.white)
                                .contentTransition(.symbolEffect(.replace))
                                .animation(.smooth(duration: 0.3), value: icon)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Adaptive Audio Level Indicator

/// Audio level visualization that scales for different platforms
struct AdaptiveAudioLevelIndicator: View {
    let level: Float
    let barCount: Int

    init(level: Float, barCount: Int = 10) {
        self.level = level
        self.barCount = barCount
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < Int(level * Float(barCount)) ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: AdaptiveSizing.audioBarWidth, height: AdaptiveSizing.audioBarHeight)
            }
        }
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

    /// Constrains the view to a maximum readable width, centered
    func adaptiveContentWidth(_ maxWidth: CGFloat? = nil) -> some View {
        frame(maxWidth: maxWidth ?? AdaptiveSizing.maxContentWidth)
    }

    /// Applies padding appropriate for the current platform
    func adaptiveContentPadding() -> some View {
        padding(.horizontal, AdaptiveSizing.contentPadding)
    }

    /// Constrains to conversation area width
    func adaptiveConversationWidth() -> some View {
        frame(maxWidth: AdaptiveSizing.conversationMaxWidth, alignment: .leading)
    }
}

// MARK: - Adaptive Model Badge

/// A model info badge that scales appropriately for different platforms
struct AdaptiveModelBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: AdaptiveSizing.badgeFontSize))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: AdaptiveSizing.badgeFontSize - 1))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: AdaptiveSizing.badgeFontSize))
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AdaptiveSizing.badgePaddingH)
        .padding(.vertical, AdaptiveSizing.badgePaddingV)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}
