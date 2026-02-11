import Foundation
import RunAnywhere
import Combine
import os

// MARK: - TTS ViewModel

/// ViewModel for Text-to-Speech functionality
///
/// Uses the simplified `RunAnywhere.speak()` API - the SDK handles all audio playback internally.
@MainActor
class TTSViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "TTS")

    // MARK: - Published Properties

    // Model State
    @Published var selectedFramework: InferenceFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?

    // Speaking State
    @Published var isSpeaking = false
    @Published var errorMessage: String?
    @Published var lastResult: TTSSpeakResult?

    // Voice Settings
    @Published var speechRate: Double = 1.0
    @Published var pitch: Double = 1.0 // while removed from the UI, the backend still supports pitch, so maintinaining it here.

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var isInitialized = false
    private var hasSubscribedToEvents = false

    // MARK: - Initialization

    /// Initialize the TTS view model
    /// This method is idempotent - calling it multiple times is safe
    func initialize() async {
        guard !isInitialized else {
            logger.debug("TTS view model already initialized, skipping")
            return
        }
        isInitialized = true

        logger.info("Initializing TTS view model")

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
        isSpeaking = true
        errorMessage = nil

        do {
            try await RunAnywhere.loadTTSModel(model.id)
            selectedFramework = model.framework
            selectedModelName = model.name.modelNameFromID()
            selectedModelId = model.id
            logger.info("TTS model loaded successfully: \(model.name)")
        } catch {
            logger.error("Failed to load TTS model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isSpeaking = false
    }

    // MARK: - Speaking

    /// Speak the given text aloud
    ///
    /// The SDK handles audio synthesis and playback internally.
    /// - Parameter text: The text to speak
    func speak(text: String) async {
        logger.info("Speaking: \(text.prefix(50))...")
        isSpeaking = true
        errorMessage = nil
        lastResult = nil

        do {
            let options = TTSOptions(
                rate: Float(speechRate),
                pitch: Float(pitch)
            )

            // SDK handles everything - synthesis AND playback
            let result = try await RunAnywhere.speak(text, options: options)
            lastResult = result

            logger.info("Speech completed: \(String(format: "%.2fs", result.duration))")
        } catch {
            logger.error("Speech failed: \(error.localizedDescription)")
            errorMessage = "Speech failed: \(error.localizedDescription)"
        }

        isSpeaking = false
    }

    /// Stop current speech
    func stopSpeaking() async {
        logger.info("Stopping speech")
        await RunAnywhere.stopSpeaking()
        isSpeaking = false
    }

    // MARK: - Cleanup

    /// Clean up resources - call from view's onDisappear
    func cleanup() {
        cancellables.removeAll()
        isInitialized = false
        hasSubscribedToEvents = false
    }

    // MARK: - SDK Event Handling

    private func subscribeToSDKEvents() {
        guard !hasSubscribedToEvents else {
            logger.debug("Already subscribed to SDK events, skipping")
            return
        }
        hasSubscribedToEvents = true

        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handleSDKEvent(event)
                }
            }
            .store(in: &cancellables)
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        // Events now come from C++ via generic BridgedEvent
        guard event.category == .tts else { return }

        switch event.type {
        case "tts_voice_load_completed":
            let voiceId = event.properties["model_id"] ?? ""
            selectedModelId = voiceId
            selectedModelName = voiceId
            logger.info("TTS voice loaded: \(voiceId)")
        case "tts_voice_unloaded":
            selectedModelId = nil
            selectedModelName = nil
            selectedFramework = nil
            logger.info("TTS voice unloaded")
        default:
            break
        }
    }

    // MARK: - Formatting Helpers

    func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            return String(format: "%.1f MB", kb / 1024.0)
        }
    }
}
