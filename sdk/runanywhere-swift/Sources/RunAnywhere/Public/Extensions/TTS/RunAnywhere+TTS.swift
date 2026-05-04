//
//  RunAnywhere+TTS.swift
//  RunAnywhere SDK
//
//  Public API for Text-to-Speech operations.
//  Calls C++ directly via CppBridge.TTS for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

@preconcurrency import AVFoundation
import CRACommons
import Foundation

// MARK: - TTS Operations

public extension RunAnywhere {

    // MARK: - Voice Loading

    /// Load a TTS voice
    /// - Parameter voiceId: The voice identifier
    /// - Throws: Error if loading fails
    static func loadTTSVoice(_ voiceId: String) async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        // Resolve voice ID to local file path
        let allModels = try await availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == voiceId }) else {
            throw SDKException.tts(.modelNotFound, "Voice '\(voiceId)' not found in registry")
        }
        guard let localPath = modelInfo.localPath else {
            throw SDKException.tts(.modelNotFound, "Voice '\(voiceId)' is not downloaded")
        }

        try await CppBridge.TTS.shared.loadVoice(localPath.path, voiceId: voiceId, voiceName: modelInfo.name)
    }

    /// Unload the currently loaded TTS voice
    static func unloadTTSVoice() async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        await CppBridge.TTS.shared.unload()
    }

    /// Check if a TTS voice is loaded
    static var isTTSVoiceLoaded: Bool {
        get async {
            await CppBridge.TTS.shared.isLoaded
        }
    }

    /// Return available TTS voices as `[RATTSVoiceInfo]` (CANONICAL_API §5).
    ///
    /// Each `RATTSVoiceInfo` carries `.id`, `.displayName`, and `.languageCode`.
    /// The list is derived from the model registry filtered to TTS-capable models.
    ///
    /// - Returns: Array of `RATTSVoiceInfo` proto values.
    static func availableTTSVoices() async -> [RATTSVoiceInfo] {
        if RunAnywhere.isInitialized,
           let voices = try? await CppBridge.TTS.shared.listVoices(),
           !voices.isEmpty {
            return voices
        }
        let allModels = await CppBridge.ModelRegistry.shared.getByFrameworks([.onnx])
        let ttsModels = allModels.filter { $0.category == .speechSynthesis }
        return ttsModels.map { model in
            var info = RATTSVoiceInfo()
            info.id = model.id
            info.displayName = model.name
            info.languageCode = "en-US" // default; real locale from model metadata if available
            return info
        }
    }

    // MARK: - Synthesis

    /// Synthesize text to speech
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - options: Synthesis options
    /// - Returns: TTS output with audio data
    static func synthesize(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) async throws -> TTSOutput {
        let output = try await synthesize(text, options: options.toRATTSOptions())
        return TTSOutput(from: output)
    }

    /// Synthesize text through the generated-proto C++ TTS ABI.
    static func synthesize(
        _ text: String,
        options: RATTSOptions
    ) async throws -> RATTSOutput {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        guard await CppBridge.TTS.shared.isLoaded else {
            throw SDKException.tts(.notInitialized, "TTS voice not loaded")
        }

        return try await CppBridge.TTS.shared.synthesize(text: text, options: options)
    }

    /// Stream synthesis — canonical form (CANONICAL_API §5).
    ///
    /// Returns an `AsyncStream<TTSAudioChunk>` where each element wraps a PCM audio chunk
    /// together with its sample rate and a `isFinal` flag.
    /// The stream closes after all chunks have been emitted or on error.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize.
    ///   - options: Synthesis options (optional).
    /// - Returns: `AsyncStream<TTSAudioChunk>` of audio chunks.
    static func synthesizeStream(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) -> AsyncStream<TTSAudioChunk> {
        let sampleRateFallback = options.sampleRate
        return AsyncStream { continuation in
            Task {
                let stream = synthesizeStream(text, options: options.toRATTSOptions())
                for await output in stream {
                    continuation.yield(
                        TTSAudioChunk(
                            audioData: output.audioData,
                            sampleRate: output.sampleRate > 0 ? Int(output.sampleRate) : sampleRateFallback,
                            isFinal: false
                        )
                    )
                }
                continuation.finish()
            }
        }
    }

    /// Stream synthesis through the generated-proto C++ TTS ABI.
    static func synthesizeStream(
        _ text: String,
        options: RATTSOptions
    ) -> AsyncStream<RATTSOutput> {
        AsyncStream { continuation in
            Task {
                guard isInitialized,
                      await CppBridge.TTS.shared.isLoaded,
                      let stream = try? await CppBridge.TTS.shared.synthesizeStream(text: text, options: options) else {
                    continuation.finish()
                    return
                }
                for await output in stream {
                    continuation.yield(output)
                }
                continuation.finish()
            }
        }
    }

    /// Stream synthesis for long text — legacy callback form (prefer `synthesizeStream(_:options:)`).
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - options: Synthesis options
    ///   - onAudioChunk: Callback for each audio chunk
    /// - Returns: TTS output with full audio data
    static func synthesizeStream(
        _ text: String,
        options: TTSOptions = TTSOptions(),
        onAudioChunk: @escaping (Data) -> Void
    ) async throws -> TTSOutput {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        guard await CppBridge.TTS.shared.isLoaded else {
            throw SDKException.tts(.notInitialized, "TTS voice not loaded")
        }

        let stream = try await CppBridge.TTS.shared.synthesizeStream(text: text, options: options.toRATTSOptions())
        var combined = Data()
        var finalOutput = RATTSOutput()
        for await output in stream {
            onAudioChunk(output.audioData)
            combined.append(output.audioData)
            finalOutput = output
        }
        finalOutput.audioData = combined
        return TTSOutput(from: finalOutput)
    }

    /// Stop current TTS synthesis
    static func stopSynthesis() async {
        await CppBridge.TTS.shared.stop()
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
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let output = try await synthesize(text, options: options)

        // Convert Float32 PCM to WAV format using C++ utility
        let wavData = try convertPCMToWAV(pcmData: output.audioData, sampleRate: Int32(options.sampleRate))

        // Play the audio using platform audio manager
        if !wavData.isEmpty {
            try await ttsAudioPlayback.play(wavData)
        }

        return TTSSpeakResult(from: output)
    }

    /// Whether speech is currently playing
    static var isSpeaking: Bool {
        get async { false }
    }

    /// Stop current speech playback
    static func stopSpeaking() async {
        ttsAudioPlayback.stop()
        await stopSynthesis()
    }

    // MARK: - Private Audio Playback

    /// Audio playback manager for TTS speak functionality
    private static let ttsAudioPlayback = AudioPlaybackManager()

    /// Convert Float32 PCM to WAV using C++ audio utilities
    private static func convertPCMToWAV(pcmData: Data, sampleRate: Int32) throws -> Data {
        guard !pcmData.isEmpty else { return Data() }

        var wavDataPtr: UnsafeMutableRawPointer?
        var wavSize: Int = 0

        let result = pcmData.withUnsafeBytes { pcmPtr in
            rac_audio_float32_to_wav(
                pcmPtr.baseAddress,
                pcmData.count,
                sampleRate,
                &wavDataPtr,
                &wavSize
            )
        }

        guard result == RAC_SUCCESS, let ptr = wavDataPtr, wavSize > 0 else {
            throw SDKException.tts(.processingFailed, "Failed to convert PCM to WAV: \(result)")
        }

        let wavData = Data(bytes: ptr, count: wavSize)
        rac_free(ptr)

        return wavData
    }
}

// MARK: - Streaming Context

private final class TTSStreamContext: @unchecked Sendable {
    let onChunk: (Data) -> Void
    var totalData = Data()

    init(onChunk: @escaping (Data) -> Void) {
        self.onChunk = onChunk
    }
}

// MARK: - Async Stream Context (canonical synthesizeStream)

/// Context bridge for the canonical `synthesizeStream(_:options:)` returning `AsyncStream<TTSAudioChunk>`.
private final class TTSAsyncStreamContext: @unchecked Sendable {
    let continuation: AsyncStream<TTSAudioChunk>.Continuation
    let sampleRate: Int

    init(continuation: AsyncStream<TTSAudioChunk>.Continuation, sampleRate: Int) {
        self.continuation = continuation
        self.sampleRate = sampleRate
    }
}
