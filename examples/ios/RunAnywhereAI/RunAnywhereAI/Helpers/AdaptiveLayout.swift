//
//  AdaptiveLayout.swift
//  RunAnywhereAI
//
//  Cross-platform adaptive layout helpers
//

import SwiftUI

// MARK: - Adaptive Modal/Sheet Wrapper
struct AdaptiveSheet<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheetContent: () -> SheetContent
    
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .sheet(isPresented: $isPresented) {
                self.sheetContent()
                    .frame(minWidth: 500, idealWidth: 600, maxWidth: 800,
                           minHeight: 400, idealHeight: 500, maxHeight: 700)
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
        configuration.label
            .buttonStyle(isPrimary ? .borderedProminent : .bordered)
            .controlSize(.regular)
        #else
        configuration.label
            .padding(.horizontal, isPrimary ? 16 : 12)
            .padding(.vertical, isPrimary ? 12 : 8)
            .background(isPrimary ? Color.accentColor : Color.secondary.opacity(0.2))
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
        self.frame(minWidth: 400, idealWidth: 600, maxWidth: 900,
                   minHeight: 300, idealHeight: 500, maxHeight: 800)
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