//
//  FlowActivationView.swift
//  RunAnywhereAI
//
//  Shown as a full-screen cover when the keyboard extension opens the main app
//  via the runanywhere://startFlow deep link.
//
//  Purpose: Start the background AVAudioSession and instruct the user to swipe
//  back to the host app. Dismisses automatically once the session is ready.
//

#if os(iOS)
import SwiftUI

struct FlowActivationView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var flowSession: FlowSessionManager

    /// Alternates between two phone illustration frames
    @State private var showSecondFrame = false
    private let animationTimer = Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: Top Bar
                HStack {
                    Spacer()
                    Button {
                        Task { await flowSession.endSession() }
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }

                Spacer()

                // MARK: Status / headline
                Group {
                    switch flowSession.sessionPhase {
                    case .activating:
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.4)
                            Text("Setting up microphone…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 60)

                    case .idle where flowSession.lastError != nil:
                        // Activation failed — show error
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text(flowSession.lastError ?? "Could not start microphone")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(height: 60)

                    case .ready:
                        // All preconditions met — instruct user to swipe back
                        Text("Swipe back to continue")
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .frame(height: 60)

                    default:
                        // .idle (initial) or .activating — show spinner
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.4)
                            Text("Setting up microphone…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: 60)
                    }
                }
                .padding(.bottom, 40)

                // MARK: Animated Phone Illustration
                PhoneIllustrationView(showSecondFrame: showSecondFrame)
                    .frame(width: 180, height: 300)
                    .padding(.bottom, 36)
                    .onReceive(animationTimer) { _ in
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showSecondFrame.toggle()
                        }
                    }

                // MARK: Explanation Text
                Text("We wish you didn't have to switch apps to use RunAnywhere, but Apple requires this step to activate the microphone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)

                Spacer()
            }
        }
        // Auto-dismiss once the session reaches ready
        .onChange(of: flowSession.sessionPhase) { _, phase in
            if case .ready = phase {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isPresented = false
                }
            }
            if case .idle = phase {
                // Activation failed — keep view open so user can see the error
            }
        }
    }
}

// MARK: - Phone Illustration

private struct PhoneIllustrationView: View {
    let showSecondFrame: Bool

    var body: some View {
        ZStack {
            // Phone outline
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color(.systemGray3), lineWidth: 2)
                )

            // Phone screen content
            VStack {
                Spacer()

                if showSecondFrame {
                    // Frame B: keyboard visible at bottom
                    VStack(spacing: 0) {
                        Spacer()
                        // Simulated keyboard strip
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray4))
                            .frame(height: 70)
                            .padding(.horizontal, 12)
                            .overlay(
                                HStack(spacing: 6) {
                                    ForEach(0..<4) { _ in
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(.systemBackground))
                                            .frame(height: 28)
                                    }
                                }
                                .padding(.horizontal, 18)
                            )
                        // Swipe indicator — bottom-right
                        HStack {
                            Spacer()
                            SwipeIndicator()
                                .padding(.trailing, 18)
                                .padding(.bottom, 10)
                        }
                    }
                } else {
                    // Frame A: RunAnywhere waveform icon centered
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        // Swipe indicator — bottom center
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
            .fill(Color.accentColor.opacity(0.7))
            .frame(width: 22, height: 22)
            .scaleEffect(isAnimating ? 1.25 : 0.9)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

#endif
