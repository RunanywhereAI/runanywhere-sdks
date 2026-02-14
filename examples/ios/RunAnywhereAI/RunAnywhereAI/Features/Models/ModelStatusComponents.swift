//
//  ModelStatusComponents.swift
//  RunAnywhereAI
//
//  Reusable components for displaying model status and onboarding
//

import SwiftUI
import RunAnywhere
#if os(macOS)
import AppKit
#endif

// MARK: - Model Load State (Local UI type)

/// Simple enum to track model loading state in the UI
enum ModelLoadState: Equatable {
    case notLoaded
    case loading
    case loaded
    case error(String)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Model Status Banner

/// A banner that shows the current model status (framework + model name) or prompts to select a model
struct ModelStatusBanner: View {
    let framework: InferenceFramework?
    let modelName: String?
    let isLoading: Bool
    let supportsStreaming: Bool
    let onSelectModel: () -> Void

    init(framework: InferenceFramework?, modelName: String?, isLoading: Bool, supportsStreaming: Bool = true, onSelectModel: @escaping () -> Void) {
        self.framework = framework
        self.modelName = modelName
        self.isLoading = isLoading
        self.supportsStreaming = supportsStreaming
        self.onSelectModel = onSelectModel
    }

    var body: some View {
        HStack(spacing: 12) {
            if isLoading {
                // Loading state
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading model...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if let framework = framework, let modelName = modelName {
                // Model loaded state
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14, weight: .semibold))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(framework.displayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            // Streaming mode indicator
                            streamingModeIndicator
                        }
                        Text(modelName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: onSelectModel) {
                        Text("Change")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.primaryAccent)
                    .controlSize(.small)
                }
            } else {
                // No model state
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text("No model selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button(action: onSelectModel) {
                        HStack(spacing: 4) {
                            Image(systemName: "cube.fill")
                            Text("Select Model")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primaryAccent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        #if os(iOS)
        .background(Color(.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(12)
    }

    /// Streaming mode indicator badge
    @ViewBuilder private var streamingModeIndicator: some View {
        HStack(spacing: 3) {
            Image(systemName: supportsStreaming ? "bolt.fill" : "square.fill")
                .font(.system(size: 8))
            Text(supportsStreaming ? "Streaming" : "Batch")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(supportsStreaming ? .green : .orange)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(supportsStreaming ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
        )
    }

    private func frameworkIcon(for framework: InferenceFramework) -> String {
        switch framework {
        case .llamaCpp: return "cpu"
        case .onnx: return "square.stack.3d.up"
        case .foundationModels: return "apple.logo"
        default: return "cube"
        }
    }

    private func frameworkColor(for framework: InferenceFramework) -> Color {
        switch framework {
        case .llamaCpp: return AppColors.primaryAccent
        case .onnx: return .purple
        case .foundationModels: return .primary
        default: return .gray
        }
    }
}

// MARK: - Model Required Overlay

/// An overlay that covers the screen when no model is selected, prompting the user to select one
struct ModelRequiredOverlay: View {
    let modality: ModelSelectionContext
    let onSelectModel: () -> Void

    @State private var circle1Offset: CGFloat = -100
    @State private var circle2Offset: CGFloat = 100
    @State private var circle3Offset: CGFloat = 0

    var body: some View {
        ZStack {
            // Animated floating circles background
            ZStack {
                // Circle 1 - Top left
                Circle()
                    .fill(modalityColor.opacity(0.15))
                    .blur(radius: 80)
                    .frame(width: 300, height: 300)
                    .offset(x: circle1Offset, y: -200)

                // Circle 2 - Bottom right
                Circle()
                    .fill(modalityColor.opacity(0.12))
                    .blur(radius: 100)
                    .frame(width: 250, height: 250)
                    .offset(x: circle2Offset, y: 300)

                // Circle 3 - Center
                Circle()
                    .fill(modalityColor.opacity(0.08))
                    .blur(radius: 90)
                    .frame(width: 280, height: 280)
                    .offset(x: -circle3Offset, y: circle3Offset)
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 8)
                    .repeatForever(autoreverses: true)
                ) {
                    circle1Offset = 100
                    circle2Offset = -100
                    circle3Offset = 80
                }
            }

            VStack(spacing: AppSpacing.xLarge) {
                Spacer()

                // Friendly icon with gradient background
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [modalityColor.opacity(0.2), modalityColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 120, height: 120)

                    Image(systemName: modalityIcon)
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [modalityColor, modalityColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                // Title
                Text(modalityTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                // Description
                Text(modalityDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                // Bottom section with glass effect button
                VStack(spacing: AppSpacing.medium) {
                    // Primary CTA with glass effect
                    if #available(iOS 26.0, *) {
                        Button(action: onSelectModel) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Get Started")
                            }
                            .font(.headline)
                            .foregroundColor(modalityColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.thinMaterial)
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, AppSpacing.xLarge)
                    } else {
                        Button(action: onSelectModel) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Get Started")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(modalityColor)
                        .padding(.horizontal, AppSpacing.xLarge)
                    }

                    // Privacy note
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption2)
                        Text("100% Private • Runs on your device")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.bottom, AppSpacing.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }

    private var modalityIcon: String {
        switch modality {
        case .llm: return "sparkles"
        case .stt: return "waveform"
        case .tts: return "speaker.wave.2.fill"
        case .voice: return "mic.circle.fill"
        case .vlm: return "camera.viewfinder"
        }
    }

    private var modalityColor: Color {
        switch modality {
        case .llm: return AppColors.primaryAccent
        case .stt: return .green
        case .tts: return AppColors.primaryPurple
        case .voice: return AppColors.primaryAccent
        case .vlm: return .orange
        }
    }

    private var modalityTitle: String {
        switch modality {
        case .llm: return "Welcome!"
        case .stt: return "Voice to Text"
        case .tts: return "Read Aloud"
        case .voice: return "Voice Assistant"
        case .vlm: return "Vision AI"
        }
    }

    private var modalityDescription: String {
        switch modality {
        case .llm: return "Choose your AI assistant and start chatting. Everything runs privately on your device."
        case .stt: return "Transcribe your speech to text with powerful on-device voice recognition."
        case .tts: return "Have any text read aloud with natural-sounding voices."
        case .voice: return "Talk naturally with your AI assistant. Let's set up the components together."
        case .vlm: return "Point your camera at anything and get AI-powered descriptions in real-time."
        }
    }
}

// MARK: - Voice Pipeline Setup View

/// A setup view specifically for Voice Assistant which requires 3 models
struct VoicePipelineSetupView: View {
    @Binding var sttModel: SelectedModelInfo?
    @Binding var llmModel: SelectedModelInfo?
    @Binding var ttsModel: SelectedModelInfo?

    // Model loading states from SDK lifecycle tracker
    var sttLoadState: ModelLoadState = .notLoaded
    var llmLoadState: ModelLoadState = .notLoaded
    var ttsLoadState: ModelLoadState = .notLoaded

    let onSelectSTT: () -> Void
    let onSelectLLM: () -> Void
    let onSelectTTS: () -> Void
    let onStartVoice: () -> Void

    var allModelsReady: Bool {
        sttModel != nil && llmModel != nil && ttsModel != nil
    }

    var allModelsLoaded: Bool {
        sttLoadState.isLoaded && llmLoadState.isLoaded && ttsLoadState.isLoaded
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.primaryAccent)

                Text("Voice Assistant Setup")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Voice requires 3 models to work together")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)

            // Model cards with load state
            VStack(spacing: 16) {
                // STT Model
                ModelSetupCard(
                    step: 1,
                    title: "Speech Recognition",
                    subtitle: "Converts your voice to text",
                    icon: "waveform",
                    color: .green,
                    selectedFramework: sttModel?.framework,
                    selectedModel: sttModel?.name,
                    loadState: sttLoadState,
                    onSelect: onSelectSTT
                )

                // LLM Model
                ModelSetupCard(
                    step: 2,
                    title: "Language Model",
                    subtitle: "Processes and responds to your input",
                    icon: "brain",
                    color: AppColors.primaryAccent,
                    selectedFramework: llmModel?.framework,
                    selectedModel: llmModel?.name,
                    loadState: llmLoadState,
                    onSelect: onSelectLLM
                )

                // TTS Model
                ModelSetupCard(
                    step: 3,
                    title: "Text to Speech",
                    subtitle: "Converts responses to audio",
                    icon: "speaker.wave.2",
                    color: .purple,
                    selectedFramework: ttsModel?.framework,
                    selectedModel: ttsModel?.name,
                    loadState: ttsLoadState,
                    onSelect: onSelectTTS
                )
            }
            .padding(.horizontal)

            Spacer()

            // Start button - enabled only when all models are loaded
            Button(action: onStartVoice) {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                    Text("Start Voice Assistant")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .disabled(!allModelsLoaded)
            .padding(.horizontal)
            .padding(.bottom, 20)

            // Status message
            if !allModelsReady {
                Text("Select all 3 models to continue")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
            } else if !allModelsLoaded {
                Text("Waiting for models to load...")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.bottom, 10)
            } else {
                Text("All models loaded and ready!")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Model Setup Card (for Voice Pipeline)

struct ModelSetupCard: View {
    let step: Int
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let selectedFramework: InferenceFramework?
    let selectedModel: String?
    var loadState: ModelLoadState = .notLoaded
    let onSelect: () -> Void

    var isConfigured: Bool {
        selectedFramework != nil && selectedModel != nil
    }

    var isLoaded: Bool {
        loadState.isLoaded
    }

    var isLoading: Bool {
        loadState.isLoading
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Step indicator with loading/loaded state
                ZStack {
                    Circle()
                        .fill(stepIndicatorColor)
                        .frame(width: 36, height: 36)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if isLoaded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    } else if isConfigured {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(step)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: icon)
                            .foregroundColor(color)
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    if let model = selectedModel {
                        HStack(spacing: 4) {
                            Text(model)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            if isLoaded {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            } else if isLoading {
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    } else {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Action / Status
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if isLoaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Loaded")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else if isConfigured {
                    Text("Change")
                        .font(.caption)
                        .foregroundColor(AppColors.primaryAccent)
                } else {
                    HStack(spacing: 4) {
                        Text("Select")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.primaryAccent)
                }
            }
            .padding(16)
            #if os(iOS)
            .background(Color(.secondarySystemBackground))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var stepIndicatorColor: Color {
        if isLoading {
            return .orange
        } else if isLoaded {
            return .green
        } else if isConfigured {
            return color
        } else {
            return Color.gray.opacity(0.2)
        }
    }

    private var borderColor: Color {
        if isLoaded {
            return .green.opacity(0.5)
        } else if isLoading {
            return .orange.opacity(0.5)
        } else if isConfigured {
            return color.opacity(0.5)
        } else {
            return .clear
        }
    }
}

// MARK: - Compact Model Indicator (for headers)

/// A compact indicator showing current model status for use in navigation bars
struct CompactModelIndicator: View {
    let framework: InferenceFramework?
    let modelName: String?
    let isLoading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let framework = framework {
                    Circle()
                        .fill(frameworkColor(for: framework))
                        .frame(width: 8, height: 8)

                    Text(modelName ?? framework.displayName)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Image(systemName: "cube")
                        .font(.caption)
                    Text("Select Model")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(framework != nil ? AppColors.primaryAccent.opacity(0.1) : AppColors.primaryAccent.opacity(0.2))
            .foregroundColor(AppColors.primaryAccent)
            .cornerRadius(8)
        }
    }

    private func frameworkColor(for framework: InferenceFramework) -> Color {
        switch framework {
        case .llamaCpp: return AppColors.primaryAccent
        case .onnx: return .purple
        case .foundationModels: return .primary
        default: return .gray
        }
    }
}

// MARK: - Previews

#Preview("Model Status Banner - Loaded") {
    VStack(spacing: 20) {
        ModelStatusBanner(
            framework: .llamaCpp,
            modelName: "SmolLM2-135M",
            isLoading: false
        ) {}

        ModelStatusBanner(
            framework: nil,
            modelName: nil,
            isLoading: false
        ) {}

        ModelStatusBanner(
            framework: .onnx,
            modelName: "whisper-tiny",
            isLoading: true
        ) {}
    }
    .padding()
}

#Preview("Model Required Overlay") {
    ModelRequiredOverlay(modality: .stt) {}
}
