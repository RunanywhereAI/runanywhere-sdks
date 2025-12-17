import SwiftUI
import RunAnywhere
import AVFoundation
import Combine
import os
#if os(macOS)
import AppKit
#endif

/// Sample texts for text-to-speech demonstration
private let sampleTTSTexts: [String] = [
    "I'm not saying I'm Batman, but have you ever seen me and Batman in the same room?",
    "According to my calculations, I should have been a millionaire by now. My calculations were wrong.",
    "I told my computer I needed a break, and now it won't stop sending me vacation ads.",
    "Why do programmers prefer dark mode? Because light attracts bugs!",
    "I speak fluent sarcasm. Unfortunately, my phone's voice assistant doesn't.",
    "I'm on a seafood diet. I see food and I eat it. Then I feel regret.",
    "My brain has too many tabs open and I can't find the one playing music.",
    "I put my phone on airplane mode but it didn't fly. Worst paper airplane ever.",
    "I'm not lazy, I'm just on energy-saving mode. Like a responsible gadget.",
    "If Monday had a face, I would politely ask it to reconsider its life choices.",
    "I tried to be normal once. Worst two minutes of my life.",
    "My favorite exercise is a cross between a lunge and a crunch. I call it lunch.",
    "I don't need anger management. I need people to stop irritating me.",
    "I'm not arguing, I'm just explaining why I'm right. There's a difference.",
    "Coffee: because adulting is hard and mornings are a cruel joke.",
    "I finally found my spirit animal. It's a sloth having a bad hair day.",
    "My wallet is like an onion. When I open it, I cry.",
    "I'm not short, I'm concentrated awesome in a compact package.",
    "Life update: currently holding it all together with one bobby pin.",
    "I would lose weight, but I hate losing.",
    "Behind every great person is a cat judging them silently.",
    "I'm on the whiskey diet. I've lost three days already.",
    "My houseplants are thriving! Just kidding, they're plastic.",
    "I don't sweat, I sparkle. Aggressively. With visible discomfort.",
    "Plot twist: the hokey pokey really IS what it's all about.",
    // On-device AI fun facts
    "Your AI assistant works even when your WiFi doesn't. How's that for independence?",
    "On-device AI means your voice data stays on your phone. Privacy first, always.",
    "Why wait for the cloud when your phone can think for itself?",
    "This voice was generated entirely on your device. No internet required!",
    "Your phone just became a lot smarter. And it didn't even need a software update.",
    "On-device processing: All the intelligence, none of the monthly subscription fees.",
    "Voice AI that runs offline? That's not magic, that's just good engineering.",
    "Your data never leaves your device. That's a promise, not a policy.",
    "Fast, private, and works anywhere. Even in airplane mode!",
    "The future of AI is local. Welcome to the future."
]

/// Dedicated Text-to-Speech view with text input and playback
struct TextToSpeechView: View {
    @StateObject private var viewModel = TTSViewModel()
    @State private var showModelPicker = false
    @State private var inputText: String = sampleTTSTexts.randomElement()
        ?? "Hello! Welcome to text to speech."

    private var hasModelSelected: Bool {
        viewModel.selectedModelName != nil
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with title
                HStack {
                    Text("Text to Speech")
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
                    isLoading: viewModel.isGenerating && viewModel.selectedModelName == nil,
                    onSelectModel: { showModelPicker = true }
                )
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Main content - only enabled when model is selected
                if hasModelSelected {

            // Input and output area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Text input section
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
                                    inputText = sampleTTSTexts.randomElement() ?? inputText
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "dice.fill")
                                    Text("Surprise me!")
                                }
                                .font(.caption)
                                .foregroundColor(.purple)
                            }
                        }
                    }

                    // Voice settings
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
                                .tint(.blue)
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
                                .tint(.purple)
                        }
                    }
                    .padding()
                    .background(AppColors.backgroundTertiary)
                    .cornerRadius(12)

                    // Generated audio info
                    if let metadata = viewModel.metadata {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Audio Info")
                                .font(.headline)
                                .foregroundColor(.primary)

                            VStack(alignment: .leading, spacing: 4) {
                                metadataRow(icon: "waveform", label: "Duration", value: String(format: "%.2fs", metadata.durationMs / 1000))
                                metadataRow(icon: "doc.text", label: "Size", value: formatBytes(metadata.audioSize))
                                metadataRow(icon: "speaker.wave.2", label: "Sample Rate", value: "\(metadata.sampleRate) Hz")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(AppColors.backgroundSecondary)
                        .cornerRadius(12)
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
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Playback progress
                if viewModel.isPlaying {
                    HStack {
                        Text(formatTime(viewModel.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ProgressView(value: viewModel.playbackProgress)
                            .tint(.purple)

                        Text(formatTime(viewModel.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 40)
                }

                // Action buttons - adaptive sizing
                HStack(spacing: 20) {
                    // Generate/Speak button
                    Button(action: {
                        Task {
                            await viewModel.generateSpeech(text: inputText)
                        }
                    }) {
                        HStack {
                            if viewModel.isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: viewModel.isSystemTTS ? "speaker.wave.2.fill" : "waveform.circle.fill")
                                    .font(.system(size: 20))
                            }
                            // System TTS plays directly, so button says "Speak" instead of "Generate"
                            Text(viewModel.isSystemTTS ? "Speak" : "Generate")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 120, idealWidth: DeviceFormFactor.current == .desktop ? 160 : 140, maxWidth: 180)
                        .frame(height: DeviceFormFactor.current == .desktop ? 56 : 50)
                        .background(inputText.isEmpty || viewModel.selectedModelName == nil ? Color.gray : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    .disabled(inputText.isEmpty || viewModel.selectedModelName == nil || viewModel.isGenerating)

                    // Play/Stop button (only available for non-System TTS models)
                    Button(action: {
                        Task {
                            await viewModel.togglePlayback()
                        }
                    }) {
                        HStack {
                            Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 20))
                            Text(viewModel.isPlaying ? "Stop" : "Play")
                                .fontWeight(.semibold)
                        }
                        .frame(minWidth: 120, idealWidth: DeviceFormFactor.current == .desktop ? 160 : 140, maxWidth: 180)
                        .frame(height: DeviceFormFactor.current == .desktop ? 56 : 50)
                        .background(viewModel.hasGeneratedAudio ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    .disabled(!viewModel.hasGeneratedAudio || viewModel.isSystemTTS)
                    .opacity(viewModel.isSystemTTS ? 0.5 : 1.0)
                }

                // Status text
                if viewModel.isSystemTTS {
                    Text(viewModel.isGenerating ? "Speaking..." : "System TTS plays directly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(viewModel.isGenerating ? "Generating speech..." : viewModel.isPlaying ? "Playing..." : "Ready")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
                .padding()
                .background(AppColors.backgroundPrimary)
                } else {
                    // No model selected - show spacer
                    Spacer()
                }
            }

            // Overlay when no model is selected
            if !hasModelSelected && !viewModel.isGenerating {
                ModelRequiredOverlay(
                    modality: .tts,
                    onSelectModel: { showModelPicker = true }
                )
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
        .onChange(of: viewModel.selectedModelName) { oldValue, newValue in
            // Set a new random funny text when a model is loaded
            if oldValue == nil && newValue != nil {
                inputText = sampleTTSTexts.randomElement() ?? inputText
            }
        }
    }

    private var statusColor: Color {
        if viewModel.isGenerating {
            return .orange
        } else if viewModel.isPlaying {
            return .green
        } else if viewModel.selectedModelName != nil {
            return .green
        } else {
            return .gray
        }
    }

    private var statusText: String {
        if viewModel.isGenerating {
            return "Generating..."
        } else if viewModel.isPlaying {
            return "Playing"
        } else if viewModel.selectedModelName != nil {
            return "Ready"
        } else {
            return "No model selected"
        }
    }

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

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            return String(format: "%.1f MB", kb / 1024.0)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - View Model

@MainActor
class TTSViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "TTS")

    // MARK: - Published Properties
    @Published var selectedFramework: LLMFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var isGenerating = false
    @Published var isPlaying = false
    @Published var hasGeneratedAudio = false
    @Published var errorMessage: String?
    @Published var metadata: TTSMetadata?
    @Published var speechRate: Double = 1.0
    @Published var pitch: Double = 1.0
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var playbackProgress: Double = 0.0
    @Published var isSystemTTS = false // System TTS plays directly, no replay available

    private var ttsComponent: TTSComponent?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    deinit {
        playbackTimer?.invalidate()
        audioPlayer?.stop()
    }

    func initialize() async {
        logger.info("Initializing TTS view model")

        // Configure audio session for playback (iOS only - macOS doesn't use AVAudioSession)
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
        #endif

        // Subscribe to model lifecycle changes from SDK
        subscribeToModelLifecycle()
    }

    /// Subscribe to SDK's model lifecycle tracker for real-time model state updates
    private func subscribeToModelLifecycle() {
        // Observe changes to loaded models via the SDK's lifecycle tracker
        ModelLifecycleTracker.shared.$modelsByModality
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modelsByModality in
                guard let self = self else { return }

                // Update TTS model state from SDK
                if let ttsState = modelsByModality[.tts] {
                    if ttsState.state.isLoaded {
                        self.selectedFramework = ttsState.framework
                        self.selectedModelName = ttsState.modelName
                        self.selectedModelId = ttsState.modelId
                        self.isSystemTTS = ttsState.framework == .systemTTS
                        self.logger.info("✅ TTS model restored from SDK: \(ttsState.modelName)")
                    }
                } else {
                    // Only clear if no model is loaded in SDK
                    if self.selectedModelId != nil {
                        self.logger.info("TTS model unloaded from SDK")
                        self.selectedFramework = nil
                        self.selectedModelName = nil
                        self.selectedModelId = nil
                        self.isSystemTTS = false
                        self.ttsComponent = nil
                    }
                }
            }
            .store(in: &cancellables)

        // Check initial state immediately
        let modelsByModality = ModelLifecycleTracker.shared.modelsByModality
        if let ttsState = modelsByModality[.tts], ttsState.state.isLoaded {
            selectedFramework = ttsState.framework
            selectedModelName = ttsState.modelName
            selectedModelId = ttsState.modelId
            isSystemTTS = ttsState.framework == .systemTTS
            logger.info("✅ TTS model found on init: \(ttsState.modelName)")

            // Recreate component from existing SDK state if needed
            Task {
                await restoreComponentIfNeeded(modelId: ttsState.modelId)
            }
        }
    }

    /// Restore the TTS component if a model is already loaded in the SDK
    private func restoreComponentIfNeeded(modelId: String) async {
        // Only restore if we don't already have a component
        guard ttsComponent == nil else { return }

        logger.info("Restoring TTS component for model: \(modelId)")
        do {
            let config = TTSConfiguration(
                voice: modelId,
                language: "en-US",
                speakingRate: Float(speechRate),
                pitch: Float(pitch),
                volume: 1.0
            )

            let component = TTSComponent(configuration: config)
            try await component.initialize()
            ttsComponent = component
            logger.info("TTS component restored successfully")
        } catch {
            logger.error("Failed to restore TTS component: \(error.localizedDescription)")
        }
    }

    /// Load a model from the unified model selection sheet
    func loadModelFromSelection(_ model: ModelInfo) async {
        logger.info("Loading TTS model from selection: \(model.name)")
        isGenerating = true
        errorMessage = nil

        do {
            // Create TTS component with framework-agnostic configuration
            let config = TTSConfiguration(
                voice: model.id,
                language: "en-US",
                speakingRate: Float(speechRate),
                pitch: Float(pitch),
                volume: 1.0
            )

            let component = TTSComponent(configuration: config)
            try await component.initialize()

            ttsComponent = component
            selectedFramework = model.preferredFramework
            selectedModelName = model.name
            selectedModelId = model.id
            // Track if this is System TTS (plays directly, no audio data for replay)
            isSystemTTS = model.preferredFramework == .systemTTS
            logger.info("TTS model loaded successfully: \(model.name) with framework: \(model.preferredFramework?.displayName ?? "unknown")")
        } catch {
            logger.error("Failed to load TTS model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    func generateSpeech(text: String) async {
        logger.info("Generating speech for text: \(text)")
        isGenerating = true
        errorMessage = nil
        hasGeneratedAudio = false

        do {
            guard let component = ttsComponent else {
                throw NSError(domain: "TTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "No TTS component loaded"])
            }

            // Use framework-agnostic TTSComponent
            let output = try await component.synthesize(text, language: "en-US")

            // System TTS plays audio directly via AVSpeechSynthesizer - it returns empty data
            // Only create audio player for frameworks that return actual audio data (e.g., ONNX/Piper)
            if output.audioData.isEmpty {
                // System TTS - audio already played directly
                logger.info("System TTS playback completed (direct playback)")
                metadata = TTSMetadata(
                    durationMs: output.duration * 1000,
                    audioSize: 0,
                    sampleRate: 16000
                )
                // Don't set hasGeneratedAudio since there's no audio to replay
            } else {
                // ONNX/Piper TTS - create audio player for playback
                try await createAudioPlayer(from: output.audioData)

                // Get sample rate from audio player format, fall back to 22050 (Piper default)
                let actualSampleRate = Int(audioPlayer?.format.sampleRate ?? 22050)

                // Set metadata
                metadata = TTSMetadata(
                    durationMs: output.duration * 1000,
                    audioSize: output.audioData.count,
                    sampleRate: actualSampleRate
                )

                hasGeneratedAudio = true
                duration = output.duration
            }
            logger.info("Speech generation complete")
        } catch {
            logger.error("Speech generation failed: \(error.localizedDescription)")
            errorMessage = "Generation failed: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    func togglePlayback() async {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let player = audioPlayer else { return }

        player.play()
        isPlaying = true

        // Start playback timer
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                self.playbackProgress = player.currentTime / player.duration
                if !player.isPlaying {
                    self.stopPlayback()
                }
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        playbackProgress = 0

        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func createAudioPlayer(from audioData: Data) async throws {
        // Stop current playback
        stopPlayback()

        // Create audio player
        audioPlayer = try AVAudioPlayer(data: audioData)
        audioPlayer?.prepareToPlay()
    }
}

// MARK: - Supporting Types

struct TTSMetadata {
    let durationMs: Double
    let audioSize: Int
    let sampleRate: Int
}
