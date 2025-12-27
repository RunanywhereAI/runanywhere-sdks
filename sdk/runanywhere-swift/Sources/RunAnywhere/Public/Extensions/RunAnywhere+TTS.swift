//
//  RunAnywhere+TTS.swift
//  RunAnywhere SDK
//
//  Public API for Text-to-Speech operations.
//  Events are tracked via EventPublisher.
//

import Foundation

// MARK: - TTS Operations

public extension RunAnywhere {

    // MARK: - Voice Loading

    /// Load a TTS voice
    /// - Parameter voiceId: The voice identifier
    /// - Throws: Error if loading fails
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func loadTTSVoice(_ voiceId: String) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await serviceContainer.ttsCapability.loadVoice(voiceId)
    }

    /// Unload the currently loaded TTS voice
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func unloadTTSVoice() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        try await serviceContainer.ttsCapability.unload()
    }

    /// Check if a TTS voice is loaded
    static var isTTSVoiceLoaded: Bool {
        get async {
            await serviceContainer.ttsCapability.isVoiceLoaded
        }
    }

    /// Get available TTS voices
    static var availableTTSVoices: [String] {
        get async {
            await serviceContainer.ttsCapability.availableVoices
        }
    }

    // MARK: - Synthesis

    /// Synthesize text to speech
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - options: Synthesis options
    /// - Returns: TTS output with audio data
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func synthesize(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) async throws -> TTSOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        return try await serviceContainer.ttsCapability.synthesize(text, options: options)
    }

    /// Stream synthesis for long text
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - options: Synthesis options
    /// - Returns: Async stream of audio data chunks
    static func synthesizeStream(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) async -> AsyncThrowingStream<Data, Error> {
        guard isSDKInitialized else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SDKError.general(.notInitialized, "SDK not initialized"))
            }
        }

        return await serviceContainer.ttsCapability.synthesizeStream(text, options: options)
    }

    /// Stop current TTS synthesis
    static func stopSynthesis() async {
        await serviceContainer.ttsCapability.stop()
    }

    // MARK: - Speak (Simple API)

    /// Speak text aloud - the simplest way to use TTS.
    ///
    /// The SDK handles audio synthesis and playback internally.
    /// Just call this method and the text will be spoken through the device speakers.
    ///
    /// ## Example
    /// ```swift
    /// // Simple usage
    /// try await RunAnywhere.speak("Hello world")
    ///
    /// // With options
    /// let result = try await RunAnywhere.speak("Hello", options: TTSOptions(rate: 1.2))
    /// print("Duration: \(result.duration)s")
    /// ```
    ///
    /// - Parameters:
    ///   - text: Text to speak
    ///   - options: Synthesis options (rate, pitch, voice, etc.)
    /// - Returns: Result containing metadata about the spoken audio
    /// - Throws: Error if synthesis or playback fails
    static func speak(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) async throws -> TTSSpeakResult {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        return try await serviceContainer.ttsCapability.speak(text, options: options)
    }

    /// Whether speech is currently playing
    static var isSpeaking: Bool {
        serviceContainer.ttsCapability.isSpeaking
    }

    /// Stop current speech playback
    static func stopSpeaking() async {
        await serviceContainer.ttsCapability.stopSpeaking()
    }
}
