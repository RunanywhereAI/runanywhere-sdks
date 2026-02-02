import SwiftUI
import RunAnywhere
#if os(macOS)
import AppKit
#endif

// MARK: - Sample Texts

/// Collection of funny sample texts for TTS demo
private let funnyTTSSampleTexts: [String] = [
    "I'm not saying I'm Batman, but have you ever seen me and Batman in the same room?",
    "According to my calculations, I should have been a millionaire by now. My calculations were wrong.",
    "I told my computer I needed a break, and now it won't stop sending me vacation ads.",
    "Why do programmers prefer dark mode? Because light attracts bugs!",
    "I speak fluent sarcasm. Unfortunately, my phone's voice assistant doesn't.",
    "My brain has too many tabs open and I can't find the one playing music.",
    "I put my phone on airplane mode but it didn't fly. Worst paper airplane ever.",
    "I'm not lazy, I'm just on energy-saving mode. Like a responsible gadget.",
    "I tried to be normal once. Worst two minutes of my life.",
    "Coffee: because adulting is hard and mornings are a cruel joke.",
    "My wallet is like an onion. When I open it, I cry.",
    "Behind every great person is a cat judging them silently.",
    "Plot twist: the hokey pokey really IS what it's all about.",
    "RunAnywhere: because your AI should work even when your WiFi doesn't.",
    "We're a Y Combinator company now. Our moms are finally proud of us.",
    "On-device AI means your voice data stays on your phone. Unlike your ex, we respect privacy.",
    "RunAnywhere: Making cloud APIs jealous since 2024.",
    "Our SDK is so fast, it finished processing before you finished reading this sentence.",
    "Why pay per API call when you can run AI locally? Your wallet called, it says thank you.",
    "Voice AI that runs offline? That's not magic, that's just good engineering. Okay, maybe a little magic."
]

// MARK: - Text-to-Speech View

/// Dedicated Text-to-Speech view with text input and instant playback
struct TextToSpeechView: View {
    @StateObject private var viewModel = TTSViewModel()
    @State private var showModelPicker = false
    @State private var inputText: String = funnyTTSSampleTexts.randomElement()
        ?? "Hello! This is a text to speech test."
    @State private var borderAnimation = false
    @State private var waveAnimation = false

    // MARK: - Computed Properties

    private var hasModelSelected: Bool {
        viewModel.selectedModelName != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 0) {
                    // Main content - only enabled when model is selected
                    if hasModelSelected {
                        mainContentView
                        controlsView
                    } else {
                        Spacer()
                    }
                }

                // Overlay when no model is selected
                if !hasModelSelected && !viewModel.isSpeaking {
                    ModelRequiredOverlay(
                        modality: .tts
                    ) { showModelPicker = true }
                }
            }
            .navigationTitle(hasModelSelected ? "Text to Speech" : "")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(!hasModelSelected)
            .toolbar {
                if hasModelSelected {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        modelButton
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showModelPicker) {
            ModelSelectionSheet(context: .tts) { model in
                Task {
                    await viewModel.loadModelFromSelection(model)
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.initialize()
            }
            borderAnimation = true
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onChange(of: viewModel.selectedModelName) { oldValue, newValue in
            // Set a new random funny text when a model is loaded
            if oldValue == nil && newValue != nil {
                inputText = funnyTTSSampleTexts.randomElement() ?? inputText
            }
        }
    }

    // MARK: - View Components

    /// Main content area with input and settings
    private var mainContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Text input section
                textInputSection

                // Voice settings section
                voiceSettingsSection

                // Speech info (shown after speaking)
                if let result = viewModel.lastResult {
                    speechInfoSection(result: result)
                }
            }
            .padding()
        }
    }

    /// Text input section with premium styling and character count
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Text")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)

            ZStack(alignment: .topLeading) {
                // Placeholder text
                if inputText.isEmpty {
                    Text("Type or paste text to speak...")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                }

                Group {
                    TextEditor(text: $inputText)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .padding(16)
                        .frame(height: 180)
                        .scrollContentBackground(.hidden)
                }
                #if os(iOS)
                .background(
                    LinearGradient(
                        colors: [
                            Color(.secondarySystemBackground),
                            Color(.tertiarySystemBackground).opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                #else
                .background(
                    LinearGradient(
                        colors: [
                            Color(NSColor.controlBackgroundColor),
                            Color(NSColor.controlBackgroundColor).opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                #endif
                .cornerRadius(16)
                .background {
                    if #available(iOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.clear)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }

            HStack {
                Text("\(inputText.count) characters")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                // Premium surprise me button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        inputText = funnyTTSSampleTexts.randomElement() ?? inputText
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("Surprise me")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.primaryPurple.opacity(0.15))
                    .foregroundColor(AppColors.primaryPurple)
                    .cornerRadius(8)
                }
            }
        }
    }

    /// Voice settings section with rate and pitch controls
    private var voiceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Voice Settings")
                .font(.headline)
                .foregroundColor(.primary)

            // Speech rate
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Speed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fx", viewModel.speechRate))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                }
                Slider(value: $viewModel.speechRate, in: 0.5...2.0, step: 0.1)
                    .tint(AppColors.primaryAccent)
            }

            // Pitch
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pitch")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fx", viewModel.pitch))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                }
                Slider(value: $viewModel.pitch, in: 0.5...2.0, step: 0.1)
                    .tint(AppColors.primaryPurple)
            }
        }
        .padding(20)
        .background(AppColors.backgroundTertiary)
        .cornerRadius(16)
    }

    /// Speech info section showing result details
    private func speechInfoSection(result: TTSSpeakResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last Speech")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 4) {
                metadataRow(
                    icon: "waveform",
                    label: "Duration",
                    value: String(format: "%.2fs", result.duration)
                )
                if result.audioSizeBytes > 0 {
                    metadataRow(
                        icon: "doc.text",
                        label: "Size",
                        value: viewModel.formatBytes(result.audioSizeBytes)
                    )
                    metadataRow(
                        icon: "speaker.wave.2",
                        label: "Format",
                        value: result.format.rawValue.uppercased()
                    )
                }
                metadataRow(
                    icon: "person.wave.2",
                    label: "Voice",
                    value: result.metadata.voice.modelNameFromID()
                )
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(AppColors.backgroundSecondary)
        .cornerRadius(12)
    }

    /// Controls section with waveform visualization and speak button
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

            // Waveform visualization when speaking
            if viewModel.isSpeaking {
                speakingWaveform
                    .transition(.scale.combined(with: .opacity))
            }

            // Speak button
            speakButton

            // Status text with premium typography
            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(AppColors.backgroundPrimary)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isSpeaking)
    }

    /// Minimal waveform visualization for speaking state
    private var speakingWaveform: some View {
        HStack(spacing: 4) {
            ForEach(0..<7) { index in
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.primaryPurple.opacity(0.8),
                                AppColors.primaryPurple.opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 5, height: waveHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                        value: waveAnimation
                    )
            }
        }
        .frame(height: 40)
        .onAppear {
            waveAnimation = true
        }
        .onDisappear {
            waveAnimation = false
        }
    }

    /// Calculate waveform bar heights with variation
    private func waveHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [20, 32, 28, 36, 28, 32, 20]
        let animatedHeights: [CGFloat] = [28, 40, 36, 44, 36, 40, 28]

        return waveAnimation ? animatedHeights[index] : heights[index]
    }

    /// Speak button - synthesizes and plays audio instantly
    private var speakButton: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(
                    action: {
                        Task {
                            if viewModel.isSpeaking {
                                await viewModel.stopSpeaking()
                            } else {
                                await viewModel.speak(text: inputText)
                            }
                        }
                    },
                    label: {
                        HStack {
                            if viewModel.isSpeaking {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Speaking...")
                                    .fontWeight(.semibold)
                            } else {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 20))
                                Text("Speak")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(minWidth: 160, idealWidth: 200, maxWidth: 240)
                        .frame(height: DeviceFormFactor.current == .desktop ? 56 : 50)
                        .background(speakButtonColor)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                )
                .disabled(inputText.isEmpty || viewModel.selectedModelName == nil)
                .glassEffect(.regular.interactive())
            } else {
                Button(
                    action: {
                        Task {
                            if viewModel.isSpeaking {
                                await viewModel.stopSpeaking()
                            } else {
                                await viewModel.speak(text: inputText)
                            }
                        }
                    },
                    label: {
                        HStack {
                            if viewModel.isSpeaking {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Speaking...")
                                    .fontWeight(.semibold)
                            } else {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 20))
                                Text("Speak")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(minWidth: 160, idealWidth: 200, maxWidth: 240)
                        .frame(height: DeviceFormFactor.current == .desktop ? 56 : 50)
                        .background(speakButtonColor)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                )
                .disabled(inputText.isEmpty || viewModel.selectedModelName == nil)
            }
        }
    }

    /// Model button for navigation bar with logo
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


    // MARK: - Helper Views

    /// Metadata row with icon, label, and value
    @ViewBuilder
    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 16)
            Text(label + ":")
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Computed UI Properties

    /// Status text based on current state
    private var statusText: String {
        if viewModel.isSpeaking {
            return "Speaking..."
        } else if viewModel.lastResult != nil {
            return "Tap Speak to hear it again"
        } else {
            return "Ready"
        }
    }

    /// Speak button color based on state
    private var speakButtonColor: Color {
        if inputText.isEmpty || viewModel.selectedModelName == nil {
            return AppColors.statusGray
        } else if viewModel.isSpeaking {
            return AppColors.statusOrange
        } else {
            return AppColors.primaryPurple
        }
    }

    private func frameworkIcon(for framework: InferenceFramework) -> String {
        switch framework {
        case .foundationModels: return "apple.logo"
        default: return "cube"
        }
    }

    private func frameworkColor(for framework: InferenceFramework) -> Color {
        switch framework {
        case .foundationModels: return .primary
        default: return .gray
        }
    }
}

// MARK: - Preview

struct TextToSpeechView_Previews: PreviewProvider {
    static var previews: some View {
        TextToSpeechView()
    }
}
