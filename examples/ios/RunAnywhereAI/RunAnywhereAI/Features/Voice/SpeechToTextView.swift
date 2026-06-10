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
    @State private var breathingAnimation = false

    private var hasModelSelected: Bool {
        viewModel.selectedModelName != nil
    }

    private var statusMessage: String {
        ""
    }

    private var waveHeights: [CGFloat] {
        breathingAnimation
            ? [24, 40, 32, 48, 28]
            : [16, 24, 20, 28, 18]
    }

    var body: some View {
        Group {
            NavigationView {
                ZStack {
                    VStack(spacing: 0) {
                        // Mode selection - Modern pill button style
                        if hasModelSelected {
                        HStack(spacing: 8) {
                            modeButton(.batch, title: "Batch", subtitle: "Record")
                            modeButton(.live, title: "Live", subtitle: "Stream")
                            modeButton(.hybrid, title: "Hybrid", subtitle: "Cloud")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        if viewModel.selectedMode == .hybrid {
                            hybridConfigurationSection
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                        }

                        // Main content - only enabled when model is selected
                        if hasModelSelected {
                        if viewModel.transcription.isEmpty && !viewModel.isRecording && !viewModel.isTranscribing {
                            // Ready state - Modern minimal design
                            VStack(spacing: 0) {
                                Spacer()

                                VStack(spacing: 48) {
                                    // Minimal waveform visualization
                                    HStack(spacing: 4) {
                                        ForEach(0..<5) { index in
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            AppColors.primaryAccent.opacity(0.8),
                                                            AppColors.primaryAccent.opacity(0.4)
                                                        ],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: 6, height: waveHeights[index])
                                                .animation(
                                                    .easeInOut(duration: 0.8)
                                                        .repeatForever(autoreverses: true)
                                                        .delay(Double(index) * 0.1),
                                                    value: breathingAnimation
                                                )
                                        }
                                    }

                                    // Clean typography
                                    VStack(spacing: 12) {
                                        Text("Ready to transcribe")
                                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                                            .foregroundColor(.primary)

                                        Text(readyModeDescription)
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .onAppear {
                                breathingAnimation = true
                            }
                        } else if viewModel.isTranscribing && viewModel.transcription.isEmpty {
                            // Processing state - Clean and centered
                            VStack(spacing: 0) {
                                Spacer()

                                ProgressView()
                                    .scaleEffect(1.2)
                                    .padding(.bottom, 12)

                                Text("Transcribing...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Spacer()
                            }
                        } else {
                            // Transcription display with ScrollView
                            ScrollView {
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

                                        if let routing = viewModel.hybridRouting {
                                            hybridRoutingSummary(routing)
                                        }
                                }
                                .padding()
                            }
                        }

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
                                inactiveColor: viewModel.isTranscribing
                                    ? AppColors.statusOrange
                                    : AppColors.primaryAccent,
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

                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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
            .navigationTitle(hasModelSelected ? "Speech to Text" : "")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
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
        .adaptiveSheet(isPresented: $showModelPicker) {
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

    // MARK: - View Components

    private var readyModeDescription: String {
        switch viewModel.selectedMode {
        case .batch:
            return "Record first, then transcribe"
        case .live:
            return "Real-time transcription"
        case .hybrid:
            return "On-device first with cloud fallback"
        }
    }

    private func modeButton(_ mode: STTMode, title: String, subtitle: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.selectedMode = mode
            }
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .opacity(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                viewModel.selectedMode == mode
                    ? AppColors.primaryAccent.opacity(0.15)
                    : Color.clear
            )
            .foregroundColor(
                viewModel.selectedMode == mode
                    ? AppColors.primaryAccent
                    : .secondary
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        viewModel.selectedMode == mode
                            ? AppColors.primaryAccent.opacity(0.3)
                            : Color.gray.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
    }

    private var hybridConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("provider", text: $viewModel.cloudProvider)
                TextField("model", text: $viewModel.cloudModel)
            }
            TextField("cloud registry id", text: $viewModel.cloudProviderId)
            SecureField("cloud API key", text: $viewModel.cloudAPIKey)
            TextField("language", text: $viewModel.cloudLanguageCode)
            Toggle("Prefer online", isOn: $viewModel.hybridPreferOnline)
            Toggle("Require network", isOn: $viewModel.hybridRequireNetwork)
            VStack(alignment: .leading, spacing: 4) {
                Text("Fallback threshold \(viewModel.hybridConfidenceThreshold, specifier: "%.2f")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $viewModel.hybridConfidenceThreshold, in: 0.0...1.0, step: 0.05)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.caption)
        .padding(12)
        #if os(iOS)
        .background(Color(.secondarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor))
        #endif
        .cornerRadius(12)
    }

    private func hybridRoutingSummary(_ routing: HybridRoutedMetadata) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Routing")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Chosen: \(routing.chosenModelID.isEmpty ? "unknown" : routing.chosenModelID)")
            Text("Fallback: \(routing.wasFallback ? "yes" : "no")")
            if !routing.primaryErrorMessage.isEmpty {
                Text("Primary: \(routing.primaryErrorMessage)")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(12)
        #if os(iOS)
        .background(Color(.tertiarySystemBackground))
        #else
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        #endif
        .cornerRadius(10)
    }

    private var modelButton: some View {
        Button {
            showModelPicker = true
        } label: {
            HStack(spacing: 6) {
                // Model logo instead of cube icon
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

                        // Framework indicator
                        if let framework = viewModel.selectedFramework {
                            HStack(spacing: 3) {
                                Image(systemName: frameworkIcon(for: framework))
                                    .font(.system(size: 7))
                                Text(framework.displayName)
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundColor(frameworkColor(for: framework))
                        }
                    }
                } else {
                    Text("Select Model")
                        .font(.caption)
                }
            }
        }
    }


    private func frameworkIcon(for framework: InferenceFramework) -> String {
        switch framework {
        case .onnx: return "square.stack.3d.up"
        case .foundationModels: return "apple.logo"
        default: return "cube"
        }
    }

    private func frameworkColor(for framework: InferenceFramework) -> Color {
        switch framework {
        case .onnx: return .purple
        case .foundationModels: return .primary
        default: return .gray
        }
    }
}
