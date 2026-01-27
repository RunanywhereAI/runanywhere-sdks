//
//  AppTheme.swift
//  LocalAIPlayground
//
//  =============================================================================
//  APP THEME - DESIGN SYSTEM
//  =============================================================================
//
//  A cohesive design system for the LocalAIPlayground app featuring:
//  - Custom color palette with semantic naming
//  - Typography scale using SF Pro and custom fonts
//  - Reusable component styles and modifiers
//  - Dark mode support out of the box
//
//  Design Inspiration: Modern AI interfaces with a warm, approachable feel
//  that balances technical capability with user-friendly aesthetics.
//
//  =============================================================================

import SwiftUI

// =============================================================================
// MARK: - Color Palette
// =============================================================================
/// Semantic color definitions for the app's visual identity.
///
/// Uses a warm coral/orange primary color with complementary neutrals,
/// creating an approachable yet professional AI interface.
// =============================================================================
extension Color {
    
    // -------------------------------------------------------------------------
    // Primary Colors
    // -------------------------------------------------------------------------
    
    /// Primary brand color - warm coral/orange
    /// Used for primary actions, active states, and key UI elements
    static let aiPrimary = Color(red: 1.0, green: 0.45, blue: 0.35)
    
    /// Secondary brand color - soft teal
    /// Used for secondary actions and complementary accents
    static let aiSecondary = Color(red: 0.25, green: 0.75, blue: 0.75)
    
    /// Accent color - golden amber
    /// Used for highlights, badges, and special states
    static let aiAccent = Color(red: 1.0, green: 0.75, blue: 0.25)
    
    // -------------------------------------------------------------------------
    // Semantic Colors
    // -------------------------------------------------------------------------
    
    /// Success state - soft green
    static let aiSuccess = Color(red: 0.35, green: 0.78, blue: 0.55)
    
    /// Warning state - warm amber
    static let aiWarning = Color(red: 1.0, green: 0.65, blue: 0.25)
    
    /// Error state - coral red
    static let aiError = Color(red: 0.95, green: 0.35, blue: 0.35)
    
    // -------------------------------------------------------------------------
    // Background Colors
    // -------------------------------------------------------------------------
    
    /// Primary background - adapts to light/dark mode
    static let aiBackground = Color("AIBackground", bundle: nil)
    
    /// Card/surface background
    static let aiSurface = Color("AISurface", bundle: nil)
    
    /// Elevated surface (modals, popovers)
    static let aiElevated = Color("AIElevated", bundle: nil)
    
    // -------------------------------------------------------------------------
    // Text Colors
    // -------------------------------------------------------------------------
    
    /// Primary text color
    static let aiTextPrimary = Color("AITextPrimary", bundle: nil)
    
    /// Secondary/muted text color
    static let aiTextSecondary = Color("AITextSecondary", bundle: nil)
    
    // -------------------------------------------------------------------------
    // Gradient Definitions
    // -------------------------------------------------------------------------
    
    /// Primary gradient for buttons and headers
    static var aiGradientPrimary: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.0, green: 0.5, blue: 0.4),
                Color(red: 1.0, green: 0.35, blue: 0.45)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Subtle background gradient
    static var aiGradientBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.96, blue: 0.94),
                Color(red: 1.0, green: 0.98, blue: 0.96)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Dark mode background gradient
    static var aiGradientBackgroundDark: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.08, blue: 0.1),
                Color(red: 0.12, green: 0.12, blue: 0.14)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    /// Mesh gradient for hero sections
    static var aiMeshGradient: some ShapeStyle {
        AngularGradient(
            colors: [
                Color(red: 1.0, green: 0.5, blue: 0.4).opacity(0.3),
                Color(red: 0.25, green: 0.75, blue: 0.75).opacity(0.2),
                Color(red: 1.0, green: 0.75, blue: 0.25).opacity(0.25),
                Color(red: 1.0, green: 0.5, blue: 0.4).opacity(0.3)
            ],
            center: .center
        )
    }
}

// =============================================================================
// MARK: - Typography
// =============================================================================
/// Custom typography scale using system fonts with specific weights and sizes.
///
/// Follows a modular scale for visual harmony across the app.
// =============================================================================
extension Font {
    
    // -------------------------------------------------------------------------
    // Display Fonts (Hero sections, large headers)
    // -------------------------------------------------------------------------
    
    /// Extra large display text
    static let aiDisplayLarge = Font.system(size: 40, weight: .bold, design: .rounded)
    
    /// Standard display text
    static let aiDisplay = Font.system(size: 32, weight: .bold, design: .rounded)
    
    // -------------------------------------------------------------------------
    // Heading Fonts
    // -------------------------------------------------------------------------
    
    /// Large heading (page titles)
    static let aiHeadingLarge = Font.system(size: 28, weight: .semibold, design: .rounded)
    
    /// Standard heading (section titles)
    static let aiHeading = Font.system(size: 22, weight: .semibold, design: .rounded)
    
    /// Small heading (card titles)
    static let aiHeadingSmall = Font.system(size: 18, weight: .semibold, design: .rounded)
    
    // -------------------------------------------------------------------------
    // Body Fonts
    // -------------------------------------------------------------------------
    
    /// Large body text
    static let aiBodyLarge = Font.system(size: 17, weight: .regular, design: .default)
    
    /// Standard body text
    static let aiBody = Font.system(size: 15, weight: .regular, design: .default)
    
    /// Small body text
    static let aiBodySmall = Font.system(size: 13, weight: .regular, design: .default)
    
    // -------------------------------------------------------------------------
    // Specialized Fonts
    // -------------------------------------------------------------------------
    
    /// Monospace font for code/technical content
    static let aiMono = Font.system(size: 14, weight: .medium, design: .monospaced)
    
    /// Caption text
    static let aiCaption = Font.system(size: 12, weight: .medium, design: .default)
    
    /// Button/label text
    static let aiLabel = Font.system(size: 15, weight: .semibold, design: .rounded)
}

// =============================================================================
// MARK: - Spacing & Layout
// =============================================================================
/// Consistent spacing values based on an 8pt grid system.
// =============================================================================
enum AISpacing {
    /// Extra small spacing (4pt)
    static let xs: CGFloat = 4
    
    /// Small spacing (8pt)
    static let sm: CGFloat = 8
    
    /// Medium spacing (16pt)
    static let md: CGFloat = 16
    
    /// Large spacing (24pt)
    static let lg: CGFloat = 24
    
    /// Extra large spacing (32pt)
    static let xl: CGFloat = 32
    
    /// 2X large spacing (48pt)
    static let xxl: CGFloat = 48
}

// =============================================================================
// MARK: - Corner Radius
// =============================================================================
/// Consistent corner radius values for UI elements.
// =============================================================================
enum AIRadius {
    /// Small radius for tags, badges (6pt)
    static let sm: CGFloat = 6
    
    /// Medium radius for buttons, inputs (12pt)
    static let md: CGFloat = 12
    
    /// Large radius for cards (16pt)
    static let lg: CGFloat = 16
    
    /// Extra large radius for modals (24pt)
    static let xl: CGFloat = 24
    
    /// Full radius for circular elements
    static let full: CGFloat = 9999
}

// =============================================================================
// MARK: - View Modifiers
// =============================================================================

// -----------------------------------------------------------------------------
// Card Style Modifier
// -----------------------------------------------------------------------------
/// Applies consistent card styling with background, shadow, and corner radius.
struct AICardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AIRadius.lg)
                    .fill(colorScheme == .dark 
                          ? Color(white: 0.15) 
                          : Color.white)
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.08),
                        radius: 12,
                        x: 0,
                        y: 4
                    )
            )
    }
}

extension View {
    /// Applies the standard AI card style.
    func aiCardStyle() -> some View {
        modifier(AICardStyle())
    }
}

// -----------------------------------------------------------------------------
// Primary Button Style
// -----------------------------------------------------------------------------
/// A prominent button style with gradient background and press animation.
struct AIPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.aiLabel)
            .foregroundStyle(.white)
            .padding(.horizontal, AISpacing.lg)
            .padding(.vertical, AISpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AIRadius.md)
                    .fill(Color.aiGradientPrimary)
                    .opacity(isEnabled ? 1 : 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AIPrimaryButtonStyle {
    /// Primary button style with gradient background.
    static var aiPrimary: AIPrimaryButtonStyle { AIPrimaryButtonStyle() }
}

// -----------------------------------------------------------------------------
// Secondary Button Style
// -----------------------------------------------------------------------------
/// A subtle button style with outline and transparent background.
struct AISecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.aiLabel)
            .foregroundStyle(Color.aiPrimary)
            .padding(.horizontal, AISpacing.lg)
            .padding(.vertical, AISpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AIRadius.md)
                    .stroke(Color.aiPrimary, lineWidth: 2)
                    .opacity(isEnabled ? 1 : 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AISecondaryButtonStyle {
    /// Secondary button style with outline.
    static var aiSecondary: AISecondaryButtonStyle { AISecondaryButtonStyle() }
}

// -----------------------------------------------------------------------------
// Icon Button Style
// -----------------------------------------------------------------------------
/// A circular icon button style.
struct AIIconButtonStyle: ButtonStyle {
    let size: CGFloat
    let backgroundColor: Color
    
    init(size: CGFloat = 44, backgroundColor: Color = .aiPrimary) {
        self.size = size
        self.backgroundColor = backgroundColor
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(backgroundColor)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// -----------------------------------------------------------------------------
// Glass Background Modifier
// -----------------------------------------------------------------------------
/// Applies a frosted glass effect background.
struct AIGlassBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AIRadius.lg)
                    .fill(.ultraThinMaterial)
                    .shadow(
                        color: Color.black.opacity(0.1),
                        radius: 8,
                        x: 0,
                        y: 2
                    )
            )
    }
}

extension View {
    /// Applies a frosted glass background effect.
    func aiGlassBackground() -> some View {
        modifier(AIGlassBackground())
    }
}

// -----------------------------------------------------------------------------
// Shimmer Loading Effect
// -----------------------------------------------------------------------------
/// A shimmer animation for loading states.
struct AIShimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.3),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 200
                }
            }
    }
}

extension View {
    /// Applies a shimmer loading animation.
    func aiShimmer() -> some View {
        modifier(AIShimmer())
    }
}

// =============================================================================
// MARK: - Feature Card Style
// =============================================================================
/// A reusable feature card with icon, title, description, and gradient accent.
struct AIFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let gradientColors: [Color]
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AISpacing.md) {
                // Icon with gradient background
                ZStack {
                    RoundedRectangle(cornerRadius: AIRadius.md)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                // Text content
                VStack(alignment: .leading, spacing: AISpacing.xs) {
                    Text(title)
                        .font(.aiHeadingSmall)
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    
                    Text(description)
                        .font(.aiBodySmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AISpacing.md)
            .aiCardStyle()
        }
        .buttonStyle(.plain)
    }
}

// =============================================================================
// MARK: - Status Badge
// =============================================================================
/// A small status indicator badge.
struct AIStatusBadge: View {
    enum Status {
        case ready, loading, error, success
        
        var color: Color {
            switch self {
            case .ready: return .aiSecondary
            case .loading: return .aiWarning
            case .error: return .aiError
            case .success: return .aiSuccess
            }
        }
        
        var icon: String {
            switch self {
            case .ready: return "checkmark.circle.fill"
            case .loading: return "arrow.circlepath"
            case .error: return "exclamationmark.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
    }
    
    let status: Status
    let text: String
    
    var body: some View {
        HStack(spacing: AISpacing.xs) {
            Image(systemName: status.icon)
                .font(.system(size: 12))
                .foregroundStyle(status.color)
                .rotationEffect(status == .loading ? .degrees(360) : .zero)
                .animation(
                    status == .loading 
                    ? .linear(duration: 1).repeatForever(autoreverses: false) 
                    : .default,
                    value: status == .loading
                )
            
            Text(text)
                .font(.aiCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AISpacing.sm)
        .padding(.vertical, AISpacing.xs)
        .background(
            Capsule()
                .fill(status.color.opacity(0.15))
        )
    }
}

// =============================================================================
// MARK: - Previews
// =============================================================================
#Preview("Feature Cards") {
    VStack(spacing: AISpacing.md) {
        AIFeatureCard(
            icon: "bubble.left.and.bubble.right.fill",
            title: "Chat with AI",
            description: "On-device LLM for private conversations",
            gradientColors: [.aiPrimary, .aiPrimary.opacity(0.7)]
        ) {}
        
        AIFeatureCard(
            icon: "waveform",
            title: "Speech to Text",
            description: "Transcribe audio using Whisper",
            gradientColors: [.aiSecondary, .aiSecondary.opacity(0.7)]
        ) {}
        
        AIFeatureCard(
            icon: "speaker.wave.2.fill",
            title: "Text to Speech",
            description: "Natural voice synthesis with Piper",
            gradientColors: [.aiAccent, .aiAccent.opacity(0.7)]
        ) {}
    }
    .padding()
}

#Preview("Buttons") {
    VStack(spacing: AISpacing.md) {
        Button("Primary Button") {}
            .buttonStyle(.aiPrimary)
        
        Button("Secondary Button") {}
            .buttonStyle(.aiSecondary)
        
        HStack(spacing: AISpacing.md) {
            AIStatusBadge(status: .ready, text: "Ready")
            AIStatusBadge(status: .loading, text: "Loading")
            AIStatusBadge(status: .error, text: "Error")
            AIStatusBadge(status: .success, text: "Success")
        }
    }
    .padding()
}

// =============================================================================
// MARK: - Model State
// =============================================================================
/// Represents the loading state of an AI model.
///
/// Used by ModelLoaderView and related components to display appropriate UI.
// =============================================================================
enum ModelState: Equatable {
    /// Model has not been downloaded or loaded
    case notLoaded
    
    /// Model is currently downloading (progress 0.0 - 1.0)
    case downloading(progress: Double)
    
    /// Model is loading into memory
    case loading
    
    /// Model is ready for use
    case ready
    
    /// An error occurred
    case error(message: String)
    
    // -------------------------------------------------------------------------
    // Convenience Properties
    // -------------------------------------------------------------------------
    
    /// Whether the model is ready to use
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
    
    /// Whether the model is in a loading state (downloading or loading)
    var isLoading: Bool {
        switch self {
        case .downloading, .loading:
            return true
        default:
            return false
        }
    }
    
    /// SF Symbol name for this state
    var statusIcon: String {
        switch self {
        case .notLoaded:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .loading:
            return "circle.dotted"
        case .ready:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }
    
    /// Color for this state
    var statusColor: Color {
        switch self {
        case .notLoaded:
            return .secondary
        case .downloading, .loading:
            return Color.aiWarning
        case .ready:
            return Color.aiSuccess
        case .error:
            return Color.aiError
        }
    }
    
    /// Human-readable status text
    var statusText: String {
        switch self {
        case .notLoaded:
            return "Not loaded"
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .loading:
            return "Loading..."
        case .ready:
            return "Ready"
        case .error(let message):
            return message
        }
    }
}
