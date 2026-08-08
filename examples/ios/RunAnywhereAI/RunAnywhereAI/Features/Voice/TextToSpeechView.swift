import SwiftUI
import RunAnywhere
#if os(macOS)
import AppKit
#endif

// MARK: - Sample Texts

/// Collection of light sample texts for text-to-speech.
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
    "RunAnywhere is so fast, it finished processing before you finished reading this sentence.",
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

    /// Main content area with input and settings
    private var mainContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Text input section
                textInputSection

                // Voice settings section
                voiceSettingsSection
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
                .cornerRadius(AppSpacing.cornerRadiusCard)
                .background {
                    if #available(iOS 26.0, macOS 26.0, *) {
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
                    // Text swapping under the cursor is a content change, not a
                    // spatial one: it gets a crossfade, not a spring. Animating
                    // a text field the user may be reading is called out in
                    // DESIGN_GUIDELINE §6.6.
                    withMotion(Motion.microFade) {
                        inputText = funnyTTSSampleTexts.randomElement() ?? inputText
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(AppTypography.system11)
                        Text("Surprise me")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.primaryPurple.opacity(0.15))
                    .foregroundColor(AppColors.primaryPurple)
                    .cornerRadius(AppSpacing.cornerRadiusRegular)
                }
            }
        }
    }

    /// Voice settings section with speech rate control
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
        }
        .padding(20)
        .background(AppColors.backgroundTertiary)
        .cornerRadius(AppSpacing.cornerRadiusCard)
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
                    // Grows from the button it belongs to rather than scaling
                    // from its own center, so it reads as the speak action
                    // expanding into a readout.
                    .transition(.scale(scale: 0.92, anchor: .bottom).combined(with: .opacity))
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
        // One signature for the whole speaking/idle change: the waveform's
        // insertion, the button, and the status line all move together.
        .motionAware(Motion.standardSpring, value: viewModel.isSpeaking)
    }

    /// Audio activity while speaking.
    ///
    /// `.indeterminate`, not a fake meter. This screen has no amplitude to draw:
    /// `TTSViewModel` publishes `isSpeaking`, and `RunAnywhere.tts.speak` returns
    /// nothing and exposes no playback level or progress. The previous version
    /// papered over that by toggling between two hardcoded height arrays on a
    /// 0.6s stagger, which looked exactly like a real waveform of the user's
    /// audio and was in fact a constant.
    private var speakingWaveform: some View {
        AudioActivityBars(mode: .indeterminate, tint: AppColors.primaryPurple)
    }

    /// Speak button - synthesizes and plays audio instantly
    private var speakButton: some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
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
                            // A button names the action it performs, not the
                            // state it is in: while speaking, tapping this stops
                            // playback, so it says Stop. "Speaking…" is a state
                            // and lives in the status line below. Android's Read
                            // aloud button already reads Stop here.
                            if viewModel.isSpeaking {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 20))
                                Text("Stop")
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
                            // A button names the action it performs, not the
                            // state it is in: while speaking, tapping this stops
                            // playback, so it says Stop. "Speaking…" is a state
                            // and lives in the status line below. Android's Read
                            // aloud button already reads Stop here.
                            if viewModel.isSpeaking {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 20))
                                Text("Stop")
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

    /// Model button for the navigation bar.
    private var modelButton: some View {
        VoiceModelChip(
            modelName: viewModel.selectedModelName,
            framework: viewModel.selectedFramework
        ) {
            showModelPicker = true
        }
    }


    // MARK: - Computed UI Properties

    /// Status text based on current state
    private var statusText: String {
        if viewModel.isSpeaking {
            return "Speaking..."
        } else if viewModel.didSpeak {
            return "\(VoiceAgentViewModel.pressVerb) Speak to hear it again"
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
