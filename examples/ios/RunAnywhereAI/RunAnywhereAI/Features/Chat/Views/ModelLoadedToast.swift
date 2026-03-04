//
//  ModelLoadedToast.swift
//  RunAnywhereAI
//
//  Toast notification for model loaded status
//

import SwiftUI

struct ModelLoadedToast: View {
    let modelName: String
    @Binding var isShowing: Bool

    var body: some View {
        VStack {
            if isShowing {
                HStack(spacing: 12) {
                    // Success icon
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)

                    // Message
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Model Ready")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("'\(modelName)' is loaded")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular.interactive())
                            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isShowing)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let modelName: String
    let duration: TimeInterval

    func body(content: Content) -> some View {
        ZStack {
            content

            ModelLoadedToast(modelName: modelName, isShowing: $isShowing)
        }
        .onChange(of: isShowing) { _, newValue in
            if newValue {
                // Auto-dismiss after duration
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    withAnimation {
                        isShowing = false
                    }
                }
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
        Color.gray.opacity(0.1).ignoresSafeArea()

        ModelLoadedToast(
            modelName: "Platform LLM",
            isShowing: .constant(true)
        )
    }
}
