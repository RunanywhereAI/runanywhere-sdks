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

    // MARK: - Computed Properties

    private var hasModelSelected: Bool {
        viewModel.selectedModelName != nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                headerView

                // Model Status Banner
                ModelStatusBanner(
                    framework: viewModel.selectedFramework,
                    modelName: viewModel.selectedModelName,
                    isLoading: viewModel.isSpeaking && viewModel.selectedModelName == nil
                ) { showModelPicker = true }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Main content - only enabled when model is selected
                if hasModelSelected {
                    mainContentView
                    Divider()
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

    /// Header with title
    private var headerView: some View {
        HStack {
            Text("Text to Speech")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top)
    }

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

    /// Text input section with editor and character count
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter Text")
                .font(.headline)
                .foregroundColor(.primary)

            TextEditor(text: $inputText)
                .font(.body)
                .padding(12)
                .frame(minHeight: 120)
                #if os(iOS)
                .background(Color(.secondarySystemBackground))
                #else
                .background(Color(NSColor.controlBackgroundColor))
                #endif
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Text("\(inputText.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        inputText = funnyTTSSampleTexts.randomElement() ?? inputText
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "dice.fill")
                        Text("Surprise me!")
                    }
                    .font(.caption)
                    .foregroundColor(AppColors.primaryPurple)
                }
            }
        }
    }

    /// Voice settings section with rate and pitch controls
    private var voiceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice Settings")
                .font(.headline)
                .foregroundColor(.primary)

            // Speech rate
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Speed")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1fx", viewModel.speechRate))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: $viewModel.speechRate, in: 0.5...2.0, step: 0.1)
                    .tint(AppColors.primaryAccent)
            }

            // Pitch
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pitch")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1fx", viewModel.pitch))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Slider(value: $viewModel.pitch, in: 0.5...2.0, step: 0.1)
                    .tint(AppColors.primaryPurple)
            }
        }
        .padding()
        .background(AppColors.backgroundTertiary)
        .cornerRadius(12)
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
                    value: result.metadata.voice
                )
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(AppColors.backgroundSecondary)
        .cornerRadius(12)
    }

    /// Controls section with speak button
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

            // Speak button
            speakButton

            // Status text
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(AppColors.backgroundPrimary)
    }

    /// Speak button - synthesizes and plays audio instantly
    private var speakButton: some View {
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
}

// MARK: - Preview

struct TextToSpeechView_Previews: PreviewProvider {
    static var previews: some View {
        TextToSpeechView()
    }
}
