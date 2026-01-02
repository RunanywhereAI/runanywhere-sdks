import SwiftUI
import RunAnywhere
#if os(macOS)
import AppKit
#endif

/// Dedicated Speech-to-Text view with real-time transcription
/// This view is purely focused on UI - all business logic is in STTViewModel
struct SpeechToTextView: View {
    @StateObject private var viewModel = STTViewModel()
    @State private var showModelPicker = false

    private var hasModelSelected: Bool {
        viewModel.selectedModelName != nil
    }

    private var statusMessage: String {
        if viewModel.isTranscribing {
            return "Processing transcription..."
        } else if viewModel.isRecording {
            return "Tap to stop recording"
        } else {
            return "Tap to start recording"
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with title
                HStack {
                    Text("Speech to Text")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)

                // Model Status Banner - Always visible
                ModelStatusBanner(
                    framework: viewModel.selectedFramework,
                    modelName: viewModel.selectedModelName,
                    isLoading: viewModel.isProcessing && viewModel.selectedModelName == nil
                ) { showModelPicker = true }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Mode selection - Batch vs Live
                if hasModelSelected {
                    Picker("Mode", selection: $viewModel.selectedMode) {
                        Text("Batch").tag(STTMode.batch)
                        Text("Live").tag(STTMode.live)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    HStack {
                        Image(systemName: viewModel.selectedMode.icon)
                            .foregroundColor(.secondary)
                        Text(viewModel.selectedMode.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }

                Divider()

                // Main content - only enabled when model is selected
                if hasModelSelected {
                    // Transcription display
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if viewModel.transcription.isEmpty && !viewModel.isRecording && !viewModel.isTranscribing {
                                // Ready state
                                VStack(spacing: 16) {
                                    Image(systemName: "mic.circle")
                                        .font(.system(size: 64))
                                        .foregroundColor(AppColors.statusGreen.opacity(0.5))

                                    Text("Ready to transcribe")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("Tap the microphone button to start recording")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                            } else if viewModel.isTranscribing && viewModel.transcription.isEmpty {
                                // Processing state (batch mode)
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)

                                    Text("Processing audio...")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("Transcribing your recording")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                            } else {
                                // Transcription display
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Transcription")
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        Spacer()

                                        if viewModel.isRecording {
                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(AppColors.statusRed)
                                                    .frame(width: 8, height: 8)
                                                Text("RECORDING")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(AppColors.statusRed)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppColors.statusRed.opacity(0.1))
                                            .cornerRadius(4)
                                        } else if viewModel.isTranscribing {
                                            HStack(spacing: 6) {
                                                ProgressView()
                                                    .scaleEffect(0.6)
                                                Text("TRANSCRIBING")
                                                    .font(.caption2)
                                                    .fontWeight(.bold)
                                                    .foregroundColor(AppColors.statusOrange)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppColors.statusOrange.opacity(0.1))
                                            .cornerRadius(4)
                                        }
                                    }

                                    Text(viewModel.transcription)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        #if os(iOS)
                                        .background(Color(.secondarySystemBackground))
                                        #else
                                        .background(Color(NSColor.controlBackgroundColor))
                                        #endif
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding()
                    }

                    Divider()

                    // Controls
                    VStack(spacing: 16) {
                        // Error message
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(AppColors.statusRed)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Audio level indicator
                        if viewModel.isRecording {
                            AdaptiveAudioLevelIndicator(level: viewModel.audioLevel)
                        }

                        // Record button
                        AdaptiveMicButton(
                            isActive: viewModel.isRecording,
                            isPulsing: false,
                            isLoading: viewModel.isProcessing || viewModel.isTranscribing,
                            activeColor: AppColors.statusRed,
                            inactiveColor: viewModel.isTranscribing ? AppColors.statusOrange : AppColors.primaryAccent,
                            icon: viewModel.isRecording ? "stop.fill" : "mic.fill"
                        ) {
                            Task {
                                await viewModel.toggleRecording()
                            }
                        }
                        .disabled(
                            viewModel.selectedModelName == nil ||
                            viewModel.isProcessing ||
                            viewModel.isTranscribing
                        )
                        .opacity(
                            viewModel.selectedModelName == nil ||
                            viewModel.isProcessing ||
                            viewModel.isTranscribing ? 0.6 : 1.0
                        )

                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(.systemBackground))
                    #else
                    .background(Color(NSColor.windowBackgroundColor))
                    #endif
                } else {
                    // No model selected - show onboarding
                    Spacer()
                }
            }

            // Overlay when no model is selected
            if !hasModelSelected && !viewModel.isProcessing {
                ModelRequiredOverlay(
                    modality: .stt
                ) { showModelPicker = true }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelSelectionSheet(context: .stt) { model in
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
}
