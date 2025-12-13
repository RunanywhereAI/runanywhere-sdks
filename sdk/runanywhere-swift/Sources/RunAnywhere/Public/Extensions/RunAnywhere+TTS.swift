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
            throw RunAnywhereError.notInitialized
        }

        try await serviceContainer.ttsCapability.loadVoice(voiceId)
    }

    /// Unload the currently loaded TTS voice
    /// - Note: Events are automatically dispatched to both EventBus and Analytics
    static func unloadTTSVoice() async throws {
        guard isSDKInitialized else {
            throw RunAnywhereError.notInitialized
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
            throw RunAnywhereError.notInitialized
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
                continuation.finish(throwing: RunAnywhereError.notInitialized)
            }
        }

        return await serviceContainer.ttsCapability.synthesizeStream(text, options: options)
    }

    /// Stop current TTS synthesis
    static func stopSynthesis() async {
        await serviceContainer.ttsCapability.stop()
    }
}
