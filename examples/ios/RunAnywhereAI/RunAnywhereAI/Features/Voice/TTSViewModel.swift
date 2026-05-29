import Foundation
import RunAnywhere
import Combine
import os

// MARK: - TTS ViewModel

/// ViewModel for Text-to-Speech functionality
///
/// Uses the simplified `RunAnywhere.speak()` API - the SDK handles all audio playback internally.
@MainActor
class TTSViewModel: VoiceComponentViewModelBase {
    // MARK: - Component Identity

    override var component: RASDKComponent { .tts }
    override var eventCategory: RAEventCategory { .tts }
    override var modelCategory: RAModelCategory { .speechSynthesis }

    // MARK: - Published Properties

    // Speaking State
    @Published var isSpeaking = false
    @Published var lastResult: RATTSSpeakResult?

    // Voice Settings
    @Published var speechRate: Double = 1.0
    // While removed from the UI, the backend still supports pitch, so we keep it here.
    @Published var pitch: Double = 1.0

    // MARK: - Initialization

    init() {
        super.init(loggerCategory: "TTS")
    }

    /// Initialize the TTS view model
    /// This method is idempotent - calling it multiple times is safe
    func initialize() async {
        guard beginInitialization() else { return }

        logger.info("Initializing TTS view model")

        subscribeToSDKEvents()
        await checkInitialModelState()
    }

    // MARK: - Model Management

    /// Load a model from the unified model selection sheet
    func loadModelFromSelection(_ model: RAModelInfo) async {
        logger.info("Loading TTS model from selection: \(model.name)")
        isSpeaking = true
        errorMessage = nil

        var request = RAModelLoadRequest()
        request.modelID = model.id
        request.category = .speechSynthesis
        let result = await RunAnywhere.loadModel(request)
        if result.success {
            selectedFramework = model.framework
            selectedModelName = model.name.modelNameFromID()
            selectedModelId = model.id
            logger.info("TTS model loaded successfully: \(model.name)")
        } else {
            logger.error("Failed to load TTS model: \(result.errorMessage)")
            errorMessage = "Failed to load model: \(result.errorMessage)"
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
            var options = RATTSOptions.defaults()
            options.speakingRate = Float(speechRate)
            options.pitch = Float(pitch)

            // SDK handles everything - synthesis AND playback
            let result = try await RunAnywhere.speak(text, options: options)
            lastResult = result

            let durationMs = Int(result.duration * 1000)
            logger.info("Speech generation complete: duration=\(durationMs)ms")
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
        cleanupBase()
    }

    // MARK: - SDK Event Handling

    /// TTS surfaces the voice id directly as its display name rather than
    /// resolving it through the model catalog.
    override func applyLoadedModel(_ model: RAModelInfo) {
        selectedModelId = model.id
        selectedModelName = model.id
    }

    override func handleSDKEvent(_ event: RASDKEvent) {
        let voiceId = event.model.modelID

        switch event.model.kind {
        case .loadCompleted:
            selectedModelId = voiceId
            selectedModelName = voiceId
            logger.info("TTS voice loaded: \(voiceId)")
        case .unloadCompleted:
            clearLoadedModel()
            logger.info("TTS voice unloaded")
        default:
            break
        }
    }

    // MARK: - Formatting Helpers

    func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            return String(format: "%.1f MB", kb / 1024.0)
        }
    }
}
