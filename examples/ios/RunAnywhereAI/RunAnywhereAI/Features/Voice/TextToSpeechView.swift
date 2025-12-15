import SwiftUI
import RunAnywhere
import AVFoundation
import Combine
import os
#if os(macOS)
import AppKit
#endif

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

/// Dedicated Text-to-Speech view with text input and playback
struct TextToSpeechView: View {
    @StateObject private var viewModel = TTSViewModel()
    @State private var showModelPicker = false
    @State private var inputText: String = funnyTTSSampleTexts.randomElement()
        ?? "Hello! This is a text to speech test."

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
                                            inputText = funnyTTSSampleTexts.randomElement() ?? inputText
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

                        // Action buttons
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
                                        Image(systemName: "waveform.circle.fill")
                                            .font(.system(size: 20))
                                    }
                                    Text("Generate")
                                        .fontWeight(.semibold)
                                }
                                .frame(minWidth: 120, idealWidth: DeviceFormFactor.current == .desktop ? 160 : 140, maxWidth: 180)
                                .frame(height: DeviceFormFactor.current == .desktop ? 56 : 50)
                                .background(inputText.isEmpty || viewModel.selectedModelName == nil ? Color.gray : Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(25)
                            }
                            .disabled(inputText.isEmpty || viewModel.selectedModelName == nil || viewModel.isGenerating)

                            // Play/Stop button
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
                            .disabled(!viewModel.hasGeneratedAudio)
                        }

                        // Status text
                        Text(viewModel.isGenerating ? "Generating speech..." : viewModel.isPlaying ? "Playing..." : "Ready")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                inputText = funnyTTSSampleTexts.randomElement() ?? inputText
            }
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
    @Published var selectedFramework: InferenceFramework?
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

    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    deinit {
        playbackTimer?.invalidate()
        audioPlayer?.stop()
    }

    func initialize() async {
        logger.info("Initializing TTS view model")

        // Configure audio session for playback (iOS only)
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
        #endif

        // Subscribe to SDK events for TTS model state
        subscribeToSDKEvents()

        // Check initial TTS voice state
        if let voiceId = await RunAnywhere.currentTTSVoiceId {
            selectedModelId = voiceId
            selectedModelName = voiceId
            logger.info("TTS voice already loaded: \(voiceId)")
        }
    }

    /// Subscribe to SDK events for TTS model state updates
    private func subscribeToSDKEvents() {
        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleSDKEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        if let ttsEvent = event as? TTSEvent {
            switch ttsEvent {
            case .modelLoadCompleted(let voiceId, _, _):
                selectedModelId = voiceId
                selectedModelName = voiceId
                logger.info("TTS voice loaded: \(voiceId)")
            case .modelUnloaded:
                selectedModelId = nil
                selectedModelName = nil
                selectedFramework = nil
                logger.info("TTS voice unloaded")
            default:
                break
            }
        }
    }

    /// Load a model from the unified model selection sheet
    func loadModelFromSelection(_ model: ModelInfo) async {
        logger.info("Loading TTS model from selection: \(model.name)")
        isGenerating = true
        errorMessage = nil

        do {
            try await RunAnywhere.loadTTSModel(model.id)
            selectedFramework = model.preferredFramework
            selectedModelName = model.name
            selectedModelId = model.id
            logger.info("TTS model loaded successfully: \(model.name)")
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
            let options = TTSOptions(
                rate: Float(speechRate),
                pitch: Float(pitch)
            )

            let output = try await RunAnywhere.synthesize(text, options: options)

            if !output.audioData.isEmpty {
                try await createAudioPlayer(from: output.audioData)

                // Get sample rate from audio player format
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
