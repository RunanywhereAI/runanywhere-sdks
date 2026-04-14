import SwiftUI
import RunAnywhere
#if os(macOS)
import AppKit
#endif

/// Dedicated Voice Activity Detection view with real-time speech detection visualization
struct VoiceActivityDetectionView: View {
    @StateObject private var viewModel = VADViewModel()
    @State private var showModelPicker = false
    @State private var pulseAnimation = false

    private var hasModelSelected: Bool {
        viewModel.selectedModelName != nil
    }

    var body: some View {
        Group {
            NavigationView {
                ZStack {
                    VStack(spacing: 0) {
                        if hasModelSelected {
                            mainContentView
                            controlsView
                        } else {
                            Spacer()
                        }
                    }

                    // Overlay when no model is selected
                    if !hasModelSelected && !viewModel.isProcessing {
                        ModelRequiredOverlay(
                            modality: .vad
                        ) { showModelPicker = true }
                    }
                }
                .navigationTitle(hasModelSelected ? "Voice Activity Detection" : "")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(!hasModelSelected)
                #endif
                .toolbar {
                    if hasModelSelected {
                        #if os(iOS)
                        ToolbarItem(placement: .navigationBarTrailing) {
                            modelButton
                        }
                        #else
                        ToolbarItem(placement: .automatic) {
                            modelButton
                        }
                        #endif
                    }
                }
            }
            #if os(iOS)
            .navigationViewStyle(.stack)
            #endif
        }
        .adaptiveSheet(isPresented: $showModelPicker) {
            ModelSelectionSheet(context: .vad) { model in
                Task {
                    await viewModel.loadModelFromSelection(model)
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.initialize()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Main Content

    private var mainContentView: some View {
        VStack(spacing: 0) {
            if !viewModel.isListening && viewModel.activityLog.isEmpty {
                // Ready state
                readyStateView
            } else {
                // Detection display
                ScrollView {
                    VStack(spacing: 20) {
                        // Speech indicator
                        speechIndicatorView
                            .padding(.top, 24)

                        // Activity log
                        if !viewModel.activityLog.isEmpty {
                            activityLogView
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Ready State

    private var readyStateView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 48) {
                // VAD icon
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .cyan.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 12) {
                    Text("Ready to detect")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Tap the mic to start detecting speech activity")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()
        }
    }

    // MARK: - Speech Indicator

    private var speechIndicatorView: some View {
        VStack(spacing: 16) {
            ZStack {
                // Outer pulse ring (only when speech detected)
                if viewModel.isSpeechDetected {
                    Circle()
                        .stroke(Color.green.opacity(0.3), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0.0 : 0.6)
                        .animation(
                            .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: pulseAnimation
                        )

                    Circle()
                        .stroke(Color.green.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseAnimation ? 1.6 : 1.0)
                        .opacity(pulseAnimation ? 0.0 : 0.4)
                        .animation(
                            .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                            value: pulseAnimation
                        )
                }

                // Main indicator circle
                Circle()
                    .fill(
                        viewModel.isSpeechDetected
                            ? Color.green.opacity(0.2)
                            : Color.gray.opacity(0.1)
                    )
                    .frame(width: 100, height: 100)

                // Inner filled circle
                Circle()
                    .fill(
                        viewModel.isSpeechDetected
                            ? Color.green
                            : Color.gray.opacity(0.3)
                    )
                    .frame(width: 60, height: 60)

                // Icon
                Image(systemName: viewModel.isSpeechDetected ? "mic.fill" : "mic.slash")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.isSpeechDetected)
            .onChange(of: viewModel.isSpeechDetected) { _, newValue in
                if newValue {
                    pulseAnimation = true
                } else {
                    pulseAnimation = false
                }
            }

            // Status label
            Text(viewModel.isSpeechDetected ? "Speech Detected" : "Silence")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(viewModel.isSpeechDetected ? .green : .secondary)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isSpeechDetected)

            // Audio level
            if viewModel.isListening {
                AdaptiveAudioLevelIndicator(level: viewModel.audioLevel)
            }
        }
    }

    // MARK: - Activity Log

    private var activityLogView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity Log")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button("Clear") {
                    viewModel.clearLog()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            ForEach(viewModel.activityLog) { entry in
                HStack(spacing: 12) {
                    Image(systemName: entry.type.icon)
                        .font(.system(size: 14))
                        .foregroundColor(entry.type == .speechStarted ? .green : .secondary)
                        .frame(width: 24)

                    Text(entry.type.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(entry.type == .speechStarted ? .primary : .secondary)

                    Spacer()

                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                #if os(iOS)
                .background(Color(.secondarySystemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 16) {
            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.statusRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Listen button
            AdaptiveMicButton(
                isActive: viewModel.isListening,
                isPulsing: viewModel.isSpeechDetected,
                isLoading: viewModel.isProcessing,
                activeColor: .green,
                inactiveColor: .cyan,
                icon: viewModel.isListening ? "stop.fill" : "mic.fill"
            ) {
                Task {
                    await viewModel.toggleListening()
                }
            }
            .disabled(
                viewModel.selectedModelName == nil || viewModel.isProcessing
            )
            .opacity(
                viewModel.selectedModelName == nil || viewModel.isProcessing ? 0.6 : 1.0
            )

            Text(viewModel.isListening ? "Listening for speech..." : "Tap to start detection")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }

    // MARK: - Model Button

    private var modelButton: some View {
        Button {
            showModelPicker = true
        } label: {
            HStack(spacing: 6) {
                if let modelName = viewModel.selectedModelName {
                    Image(getModelLogo(for: modelName))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 36, height: 36)
                        .cornerRadius(4)
                } else {
                    Image(systemName: "cube")
                        .font(.system(size: 14))
                }

                if let modelName = viewModel.selectedModelName {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(modelName.shortModelName())
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        if let framework = viewModel.selectedFramework {
                            HStack(spacing: 3) {
                                Image(systemName: "cube")
                                    .font(.system(size: 7))
                                Text(framework.displayName)
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundColor(.gray)
                        }
                    }
                } else {
                    Text("Select Model")
                        .font(.caption)
                }
            }
        }
    }
}

// MARK: - Preview

struct VoiceActivityDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceActivityDetectionView()
    }
}
