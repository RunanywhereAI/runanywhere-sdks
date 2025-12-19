import Foundation
import RunAnywhere
import AVFoundation
import Combine
import os

// MARK: - Supporting Types

/// Metadata about generated TTS audio
struct TTSMetadata {
    let durationMs: Double
    let audioSize: Int
    let sampleRate: Int
}

// MARK: - TTS ViewModel

/// ViewModel for Text-to-Speech functionality
/// Handles all business logic for TTS including:
/// - Voice/model selection and loading
/// - Speech synthesis
/// - Audio playback management
/// - Playback state tracking
@MainActor
class TTSViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "TTS")

    // MARK: - Published Properties

    // Model State
    @Published var selectedFramework: InferenceFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?

    // Generation State
    @Published var isGenerating = false
    @Published var hasGeneratedAudio = false
    @Published var errorMessage: String?
    @Published var metadata: TTSMetadata?

    // Voice Settings
    @Published var speechRate: Double = 1.0
    @Published var pitch: Double = 1.0

    // Playback State
    @Published var isPlaying = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var playbackProgress: Double = 0.0

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization State (for idempotency)

    private var isInitialized = false
    private var hasSubscribedToEvents = false

    // MARK: - Initialization

    /// Initialize the TTS view model and configure audio session
    /// This method is idempotent - calling it multiple times is safe
    func initialize() async {
        guard !isInitialized else {
            logger.debug("TTS view model already initialized, skipping")
            return
        }
        isInitialized = true

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

    // MARK: - Model Management

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

    // MARK: - Speech Generation

    /// Generate speech from text
    /// - Parameter text: The text to synthesize
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

    // MARK: - Playback Control

    /// Toggle playback state (play/stop)
    func togglePlayback() async {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    /// Start audio playback
    private func startPlayback() {
        guard let player = audioPlayer else { return }

        player.play()
        isPlaying = true

        // Start playback timer for progress updates
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                self.playbackProgress = player.duration > 0 ? player.currentTime / player.duration : 0
                if !player.isPlaying {
                    self.stopPlayback()
                }
            }
        }
    }

    /// Stop audio playback and reset playback state
    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        playbackProgress = 0

        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    /// Create audio player from audio data
    /// - Parameter audioData: The audio data to play
    private func createAudioPlayer(from audioData: Data) async throws {
        // Stop current playback
        stopPlayback()

        // Create audio player
        audioPlayer = try AVAudioPlayer(data: audioData)
        audioPlayer?.prepareToPlay()
    }

    // MARK: - Cleanup

    /// Clean up resources - call from view's onDisappear
    /// This replaces deinit cleanup to comply with Swift 6 concurrency
    func cleanup() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        cancellables.removeAll()

        // Reset initialization flags to allow re-initialization if needed
        isInitialized = false
        hasSubscribedToEvents = false
    }

    // MARK: - SDK Event Handling

    /// Subscribe to SDK events for TTS model state updates
    private func subscribeToSDKEvents() {
        guard !hasSubscribedToEvents else {
            logger.debug("Already subscribed to SDK events, skipping")
            return
        }
        hasSubscribedToEvents = true

        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                // Defer state modifications to avoid "Publishing changes within view updates" warning
                Task { @MainActor in
                    self?.handleSDKEvent(event)
                }
            }
            .store(in: &cancellables)
    }

    /// Handle SDK events related to TTS
    private func handleSDKEvent(_ event: any SDKEvent) {
        if let ttsEvent = event as? TTSEvent {
            switch ttsEvent {
            case .modelLoadCompleted(let voiceId, _, _, _):
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

    // MARK: - Formatting Helpers

    /// Format bytes to human-readable string
    func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            return String(format: "%.1f MB", kb / 1024.0)
        }
    }

    /// Format time in seconds to MM:SS format
    func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
