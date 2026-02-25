//
//  FlowActivationView.swift
//  YapRun
//
//  Full-screen cover shown when the keyboard extension opens the main app
//  via the yaprun://startFlow deep link.
//
//  Starts the background AVAudioSession and instructs the user to swipe
//  back to the host app. Dismisses automatically once ready.
//

#if os(iOS)
import Combine
import SwiftUI

struct FlowActivationView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var flowSession: FlowSessionManager

    @State private var showSecondFrame = false
    private let animationTimer = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.backgroundPrimaryDark, AppColors.backgroundSecondaryDark],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar
                HStack {
                    Spacer()
                    Button {
                        Task { await flowSession.endSession() }
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(12)
                            .background(AppColors.overlayMedium, in: Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }

                Spacer()

                // Status / headline
                Group {
                    switch flowSession.sessionPhase {
                    case .activating:
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(AppColors.primaryAccent)
                                .scaleEffect(1.4)
                            Text("Setting up microphone...")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(height: 60)

                    case .idle where flowSession.lastError != nil:
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundStyle(AppColors.primaryAccent)
                            Text(flowSession.lastError ?? "Could not start microphone")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(height: 60)

                    case .ready:
                        Text("Swipe back to continue")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .frame(height: 60)

                    default:
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(AppColors.primaryAccent)
                                .scaleEffect(1.4)
                            Text("Setting up microphone...")
                                .font(.subheadline)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .frame(height: 60)
                    }
                }
                .padding(.bottom, 40)

                // Animated Phone Illustration
                PhoneIllustrationView(showSecondFrame: showSecondFrame)
                    .frame(width: 180, height: 300)
                    .padding(.bottom, 36)
                    .onReceive(animationTimer) { _ in
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showSecondFrame.toggle()
                        }
                    }

                Text("We wish you didn't have to switch apps, but Apple requires this step to activate the microphone.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)

                Spacer()
            }
        }
        .onChange(of: flowSession.sessionPhase) { _, phase in
            if case .ready = phase {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPresented = false
                }
            }
        }
    }
}

// MARK: - Phone Illustration

private struct PhoneIllustrationView: View {
    let showSecondFrame: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppColors.backgroundTertiaryDark)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    AppColors.primaryAccent.opacity(0.3),
                                    AppColors.primaryAccent.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )

            VStack {
                Spacer()

                if showSecondFrame {
                    VStack(spacing: 0) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.backgroundGray5Dark)
                            .frame(height: 70)
                            .padding(.horizontal, 12)
                            .overlay(
                                HStack(spacing: 6) {
                                    ForEach(0..<4, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(AppColors.backgroundSecondaryDark)
                                            .frame(height: 28)
                                    }
                                }
                                .padding(.horizontal, 18)
                            )
                        HStack {
                            Spacer()
                            SwipeIndicator()
                                .padding(.trailing, 18)
                                .padding(.bottom, 10)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(AppColors.primaryAccent)
                        SwipeIndicator()
                            .padding(.top, 20)
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(16)
            .clipped()
        }
    }
}

private struct SwipeIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(AppColors.primaryAccent.opacity(0.7))
            .frame(width: 22, height: 22)
            .scaleEffect(isAnimating ? 1.25 : 0.9)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

#endif
