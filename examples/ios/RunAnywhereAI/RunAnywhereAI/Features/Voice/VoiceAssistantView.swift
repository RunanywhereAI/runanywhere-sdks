import SwiftUI
import RunAnywhere
#if canImport(UIKit)
import UIKit
#endif

struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAgentViewModel()
    @State private var showModelInfo = false
    @State private var showModelSelection = false
    @State private var showSTTModelSelection = false
    @State private var showLLMModelSelection = false
    @State private var showTTSModelSelection = false

    // Particle animation states
    @State private var amplitude: Float = 0.0
    @State private var morphProgress: Float = 0.0
    @State private var scatterAmount: Float = 0.0
    @State private var touchPoint: SIMD2<Float> = .zero
    @Environment(\.colorScheme) var colorScheme

    private let animationTimer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            #if os(macOS)
            macOSContent
            #else
            iOSContent
            #endif
        }
        .adaptiveSheet(isPresented: $showModelSelection) {
            modelSelectionSheet
        }
        .adaptiveSheet(isPresented: $showSTTModelSelection) {
            ModelSelectionSheet(context: .stt) { model in
                viewModel.setSTTModel(model)
            }
        }
        .adaptiveSheet(isPresented: $showLLMModelSelection) {
            ModelSelectionSheet(context: .llm) { model in
                viewModel.setLLMModel(model)
            }
        }
        .adaptiveSheet(isPresented: $showTTSModelSelection) {
            ModelSelectionSheet(context: .tts) { model in
                viewModel.setTTSModel(model)
            }
        }
        .onAppear {
            Task {
                if !viewModel.isInitialized {
                    await viewModel.initialize()
                } else {
                    viewModel.refreshComponentStatesFromSDK()
                }
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

#if os(macOS)
// MARK: - macOS Content
extension VoiceAssistantView {
    private var macOSContent: some View {
        VStack(spacing: 0) {
            macOSToolbar
            Divider()
            if showModelInfo {
                modelInfoSection
            }
            macOSConversationArea
            Spacer()
            controlArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var macOSToolbar: some View {
        HStack {
            Button(action: {
                showModelSelection = true
            }, label: {
                Label("Models", systemImage: "cube")
            })
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)

            Spacer()

            HStack(spacing: AppSpacing.small) {
                Circle()
                    .fill(viewModel.statusColor.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.sessionState.displayName)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    showModelInfo.toggle()
                }
            }, label: {
                Label(
                    showModelInfo ? "Hide Info" : "Show Info",
                    systemImage: "info.circle"
                )
            })
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var macOSConversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !viewModel.currentTranscript.isEmpty {
                        ConversationBubble(
                            speaker: "You",
                            message: viewModel.currentTranscript,
                            isUser: true
                        )
                        .id("user")
                    }

                    if !viewModel.assistantResponse.isEmpty {
                        ConversationBubble(
                            speaker: "Assistant",
                            message: viewModel.assistantResponse,
                            isUser: false
                        )
                        .id("assistant")
                    }

                    if viewModel.currentTranscript.isEmpty && viewModel.assistantResponse.isEmpty {
                        emptyStatePlaceholder(text: "Click the microphone to start")
                    }
                }
                .padding(.horizontal, AdaptiveSizing.contentPadding)
                .padding(.vertical, 20)
                .adaptiveConversationWidth()
            }
            .onChange(of: viewModel.assistantResponse) { _ in
                withAnimation {
                    proxy.scrollTo("assistant", anchor: .bottom)
                }
            }
        }
    }
}
#endif

#if os(iOS)
// MARK: - iOS Content
extension VoiceAssistantView {
    private var iOSContent: some View {
        ZStack {
            if !viewModel.allModelsLoaded {
                setupView
            } else {
                mainVoiceUI
            }
        }
    }

    private var setupView: some View {
        VoicePipelineSetupView(
            sttModel: Binding(
                get: { viewModel.sttModel },
                set: { viewModel.sttModel = $0 }
            ),
            llmModel: Binding(
                get: { viewModel.llmModel },
                set: { viewModel.llmModel = $0 }
            ),
            ttsModel: Binding(
                get: { viewModel.ttsModel },
                set: { viewModel.ttsModel = $0 }
            ),
            sttLoadState: viewModel.sttModelState,
            llmLoadState: viewModel.llmModelState,
            ttsLoadState: viewModel.ttsModelState,
            onSelectSTT: { showSTTModelSelection = true },
            onSelectLLM: { showLLMModelSelection = true },
            onSelectTTS: { showTTSModelSelection = true },
            onStartVoice: {
                // All models loaded, nothing to do here
            }
        )
    }

    private var mainVoiceUI: some View {
        ZStack {
            // Background particles animation - centered
            GeometryReader { geometry in
                VoiceAssistantParticleView(
                    amplitude: amplitude,
                    morphProgress: morphProgress,
                    scatterAmount: scatterAmount,
                    touchPoint: touchPoint,
                    isDarkMode: colorScheme == .dark
                )
                .frame(width: min(geometry.size.width, geometry.size.height) * 0.9)
                .frame(width: min(geometry.size.width, geometry.size.height) * 0.9)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2 - 50)
                .allowsHitTesting(false)
            }

            // Main UI overlay
            VStack(spacing: 0) {
                iOSHeader
                if showModelInfo {
                    modelInfoSection
                }
                iOSConversationArea
                Spacer()
                iOSControlArea
            }
        }
        .background(Color(.systemBackground))
        .onReceive(animationTimer) { _ in
            updateAnimation()
        }
    }

    private var iOSHeader: some View {
        HStack {
            Button(action: {
                showModelSelection = true
            }, label: {
                Image(systemName: "cube")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            })

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    showModelInfo.toggle()
                }
            }, label: {
                Image(systemName: showModelInfo ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Circle())
            })
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var iOSConversationArea: some View {
        // Conversation area is now hidden - messages shown as toast at bottom
        Spacer()
    }

    private var iOSControlArea: some View {
        VStack(spacing: 20) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.statusRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Scrollable markdown response - streaming real-time
            if !viewModel.assistantResponse.isEmpty {
                ScrollView {
                    ScrollViewReader { proxy in
                        VStack {
                            AdaptiveMarkdownText(
                                viewModel.assistantResponse,
                                font: .body,
                                color: .primary
                            )
                            .multilineTextAlignment(.center)
                            .id("responseEnd")
                        }
                        .padding(.horizontal, 30)
                        .onChange(of: viewModel.assistantResponse) { _ in
                            withAnimation {
                                proxy.scrollTo("responseEnd", anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
                .animation(.none, value: viewModel.assistantResponse)
            }

            micButtonSection

            Text(viewModel.instructionText)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 30)
    }

    private var audioLevelIndicator: some View {
        VStack(spacing: 8) {
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

            AdaptiveAudioLevelIndicator(level: viewModel.audioLevel)
        }
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: viewModel.audioLevel)
    }
}
#endif

// MARK: - Shared Components

extension VoiceAssistantView {
    private var modelInfoSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 15) {
                ModelBadge(
                    icon: "brain",
                    label: "LLM",
                    value: viewModel.currentLLMModel,
                    color: AppColors.primaryAccent
                )
                ModelBadge(
                    icon: "waveform",
                    label: "STT",
                    value: viewModel.currentSTTModel,
                    color: AppColors.statusGreen
                )
                ModelBadge(
                    icon: "speaker.wave.2",
                    label: "TTS",
                    value: viewModel.currentTTSModel,
                    color: AppColors.primaryPurple
                )
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 15)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func emptyStatePlaceholder(text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var controlArea: some View {
        VStack(spacing: 20) {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(AppColors.statusRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            micButtonSection

            Text(viewModel.instructionText)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 30)
    }

    private var micButtonSection: some View {
        let isLoading = viewModel.sessionState == .connecting
            || (viewModel.isProcessing && !viewModel.isListening)

        return HStack {
            Spacer()

            AdaptiveMicButton(
                isActive: viewModel.isListening,
                isPulsing: viewModel.isSpeechDetected,
                isLoading: isLoading,
                activeColor: viewModel.micButtonColor.swiftUIColor,
                inactiveColor: viewModel.micButtonColor.swiftUIColor,
                icon: viewModel.micButtonIcon
            ) {
                Task {
                    if viewModel.isActive {
                        await viewModel.stopConversation()
                    } else {
                        await viewModel.startConversation()
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - Model Selection Sheet

extension VoiceAssistantView {
    private var modelSelectionSheet: some View {
        NavigationView {
            VoicePipelineSetupView(
                sttModel: Binding(
                    get: { viewModel.sttModel },
                    set: { viewModel.sttModel = $0 }
                ),
                llmModel: Binding(
                    get: { viewModel.llmModel },
                    set: { viewModel.llmModel = $0 }
                ),
                ttsModel: Binding(
                    get: { viewModel.ttsModel },
                    set: { viewModel.ttsModel = $0 }
                ),
                sttLoadState: viewModel.sttModelState,
                llmLoadState: viewModel.llmModelState,
                ttsLoadState: viewModel.ttsModelState,
                onSelectSTT: {
                    showModelSelection = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showSTTModelSelection = true
                    }
                },
                onSelectLLM: {
                    showModelSelection = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showLLMModelSelection = true
                    }
                },
                onSelectTTS: {
                    showModelSelection = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showTTSModelSelection = true
                    }
                },
                onStartVoice: {
                    showModelSelection = false
                }
            )
            .navigationTitle("Voice Models")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showModelSelection = false
                    }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showModelSelection = false
                    }
                }
            }
            #endif
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }

    // MARK: - Animation Helpers
    private func updateAnimation() {
        // Target morph: 0 = sphere (idle/thinking), 1 = ring (listening/speaking)
        let isListening = viewModel.sessionState == .listening
        let isSpeaking = viewModel.sessionState == .speaking
        let isActive = isListening || isSpeaking
        let targetMorph: Float = isActive ? 1.0 : 0.0

        // Smooth morph transition
        let morphDiff = targetMorph - morphProgress
        morphProgress += morphDiff * 0.04
        morphProgress = max(0, min(1, morphProgress))

        // Scatter decay
        if scatterAmount > 0.001 {
            scatterAmount *= 0.92
        } else {
            scatterAmount = 0
        }

        // Audio amplitude - reactive to both input (listening) and output (speaking)
        if isListening {
            // Use real audio level from microphone
            let realAudioLevel = viewModel.audioLevel
            // Smooth interpolation for natural movement
            amplitude = amplitude * 0.7 + realAudioLevel * 0.3
            // Clamp to reasonable range
            amplitude = max(0.0, min(1.0, amplitude))
        } else if isSpeaking {
            // TTS output - realistic speech-like pulse simulation
            let time = Float(Date().timeIntervalSinceReferenceDate)

            // Multiple frequency components for natural speech rhythm
            let basePulse: Float = 0.35
            let primaryWave = sin(time * 3.5) * 0.2         // Main speech rhythm
            let secondaryWave = sin(time * 7.0) * 0.1       // Phoneme-like variation
            let randomNoise = Float.random(in: -0.05...0.15) // Natural variation

            let targetAmplitude = basePulse + abs(primaryWave) + abs(secondaryWave) * 0.5 + randomNoise

            // Smooth interpolation to avoid jarring changes
            amplitude = amplitude * 0.75 + targetAmplitude * 0.25
            amplitude = max(0.0, min(1.0, amplitude))
        } else {
            // Gentle decay when not active
            amplitude = amplitude * 0.95
        }
    }
}

// MARK: - Preview
struct VoiceAssistantView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceAssistantView()
    }
}
