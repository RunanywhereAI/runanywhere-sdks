import Foundation
import RunAnywhere
import Combine
import os

// MARK: - TTS ViewModel

/// ViewModel for Text-to-Speech functionality
///
/// Uses `RunAnywhere.tts.speak()` - the SDK handles all audio playback internally.
@MainActor
class TTSViewModel: VoiceComponentViewModelBase {
    // MARK: - Component Identity

    override var component: RASDKComponent { .tts }
    override var eventCategory: RAEventCategory { .tts }
    override var modelCategory: RAModelCategory { .speechSynthesis }

    // MARK: - Published Properties

    // Speaking State
    @Published var isSpeaking = false

    /// True once a phrase has been spoken in this session. `tts.speak` returns
    /// no metrics, so this is all the UI can report about the last utterance.
    @Published private(set) var didSpeak = false

    // Voice Settings
    //
    // Speed is the whole control set, deliberately, and the same on all four
    // apps. A `pitch` property lived here with no slider behind it, which read
    // like a control that had gone missing rather than one that was never
    // offered; iOS is the source of truth for that decision, so the property is
    // gone and `TtsOptions` is passed speed only.
    @Published var speechRate: Double = 1.0

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
        isSpeaking = true
        await loadModel(from: model)
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
        didRequestStop = false

        do {
            // `tts.speak` returns the moment playback *starts* — synthesis is
            // awaited, playout is not (see its doc comment: "let handle = try
            // await ...; await handle.waitForPlayout()"). Treating that return
            // as "finished" flipped `isSpeaking` false while the speaker was
            // still talking, which took the Stop control and the waveform off
            // screen for the whole utterance and left the status line claiming
            // the phrase had already been read. The handle is the only thing
            // that knows when the sound actually ends.
            let handle = try await RunAnywhere.tts.speak(
                text,
                options: TtsOptions(speed: Float(speechRate))
            )
            activeSpeech = handle
            await handle.waitForPlayout()
            activeSpeech = nil
            // A stopped utterance was never heard in full, so it must not leave
            // the screen offering to play it "again".
            if !handle.interrupted {
                didSpeak = true
            }
            logger.info("Speech playback finished")
        } catch {
            // A user- or teardown-initiated stop surfaces here as
            // `.playbackInterrupted`; that is expected, not a failure to report.
            if !didRequestStop {
                logger.error("Speech failed: \(error.localizedDescription)")
                errorMessage = "Speech failed: \(error.localizedDescription)"
            }
        }

        activeSpeech = nil
        isSpeaking = false
    }

    /// Set when playback is stopped intentionally (Stop button or teardown) so the
    /// `.playbackInterrupted` thrown back into `speak` isn't shown as an error.
    private var didRequestStop = false

    /// The utterance currently playing out, if any.
    private var activeSpeech: SpeechHandle?

    /// Stop current speech
    func stopSpeaking() async {
        logger.info("Stopping speech")
        didRequestStop = true
        // Interrupt this utterance through its own handle rather than the
        // deprecated whole-engine `tts.stop()`; it also resolves the
        // `waitForPlayout()` above, so `speak` unwinds instead of hanging.
        if let handle = activeSpeech {
            await handle.interrupt()
        } else {
            await RunAnywhere.tts.stop()
        }
        isSpeaking = false
    }

    // MARK: - Cleanup

    /// Clean up resources - call from view's onDisappear
    func cleanup() {
        // Stop any in-flight playback so speech doesn't keep playing after the
        // screen is dismissed (mirrors STT/VAD cleanup stopping capture).
        didRequestStop = true
        let closing = activeSpeech
        activeSpeech = nil
        Task {
            if let closing {
                await closing.interrupt()
            } else {
                await RunAnywhere.tts.stop()
            }
        }
        cleanupBase()
    }

    // MARK: - SDK Event Handling

    /// TTS surfaces the voice id directly as its display name rather than
    /// resolving it through the model catalog.
    override func applyLoadedModel(_ model: RAModelInfo) {
        selectedModelId = model.id
        selectedModelName = model.id
    }
}
