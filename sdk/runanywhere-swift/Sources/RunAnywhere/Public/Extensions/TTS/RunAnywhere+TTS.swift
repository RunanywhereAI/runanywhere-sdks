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
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.TTS.shared.getHandle()

        guard await CppBridge.TTS.shared.isLoaded else {
            throw SDKException.tts(.notInitialized, "TTS voice not loaded")
        }

        let voiceId = await CppBridge.TTS.shared.currentVoiceId ?? "unknown"
        let startTime = Date()

        // Build C options
        var cOptions = rac_tts_options_t()
        cOptions.rate = options.rate
        cOptions.pitch = options.pitch
        cOptions.volume = options.volume
        cOptions.sample_rate = Int32(options.sampleRate)

        // Synthesize (C++ emits events)
        var ttsResult = rac_tts_result_t()
        defer { rac_tts_result_free(&ttsResult) }
        let synthesizeResult = text.withCString { textPtr in
            rac_tts_component_synthesize(handle, textPtr, &cOptions, &ttsResult)
        }

        guard synthesizeResult == RAC_SUCCESS else {
            throw SDKException.tts(.processingFailed, "Synthesis failed: \(synthesizeResult)")
        }

        let endTime = Date()
        let processingTime = endTime.timeIntervalSince(startTime)

        // Extract audio data
        let audioData: Data
        if let audioPtr = ttsResult.audio_data, ttsResult.audio_size > 0 {
            audioData = Data(bytes: audioPtr, count: ttsResult.audio_size)
        } else {
            audioData = Data()
        }

        let sampleRate = Int(ttsResult.sample_rate)
        let numSamples = audioData.count / 4  // Float32 = 4 bytes
        let durationSec = Double(numSamples) / Double(sampleRate)

        let metadata = TTSSynthesisMetadata(
            voice: voiceId,
            language: options.language,
            processingTime: processingTime,
            characterCount: text.count
        )

        return TTSOutput(
            audioData: audioData,
            format: options.audioFormat,
            duration: durationSec,
            phonemeTimestamps: nil,
            metadata: metadata
        )
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
        AsyncStream { continuation in
            Task {
                guard isInitialized,
                      let handle = try? await CppBridge.TTS.shared.getHandle(),
                      await CppBridge.TTS.shared.isLoaded else {
                    continuation.finish()
                    return
                }

                var cOptions = rac_tts_options_t()
                cOptions.rate = options.rate
                cOptions.pitch = options.pitch
                cOptions.volume = options.volume
                cOptions.sample_rate = Int32(options.sampleRate)
                let sampleRate = options.sampleRate

                let context = TTSAsyncStreamContext(continuation: continuation, sampleRate: sampleRate)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                let _ = text.withCString { textPtr in
                    rac_tts_component_synthesize_stream(
                        handle,
                        textPtr,
                        &cOptions,
                        { audioPtr, audioSize, userData in
                            guard let audioPtr = audioPtr, let userData = userData else { return }
                            let ctx = Unmanaged<TTSAsyncStreamContext>.fromOpaque(userData)
                                .takeUnretainedValue()
                            let audioData = Data(bytes: audioPtr, count: audioSize)
                            let chunk = TTSAudioChunk(audioData: audioData, sampleRate: ctx.sampleRate, isFinal: false)
                            ctx.continuation.yield(chunk)
                        },
                        contextPtr
                    )
                }

                Unmanaged<TTSAsyncStreamContext>.fromOpaque(contextPtr).release()
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

        let handle = try await CppBridge.TTS.shared.getHandle()

        guard await CppBridge.TTS.shared.isLoaded else {
            throw SDKException.tts(.notInitialized, "TTS voice not loaded")
        }

        let voiceId = await CppBridge.TTS.shared.currentVoiceId ?? "unknown"
        let startTime = Date()

        // Build C options
        var cOptions = rac_tts_options_t()
        cOptions.rate = options.rate
        cOptions.pitch = options.pitch
        cOptions.volume = options.volume
        cOptions.sample_rate = Int32(options.sampleRate)

        // Create callback context - owns its own Data
        let context = TTSStreamContext(onChunk: onAudioChunk)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        let streamResult = text.withCString { textPtr in
            rac_tts_component_synthesize_stream(
                handle,
                textPtr,
                &cOptions,
                { audioPtr, audioSize, userData in
                    guard let audioPtr = audioPtr, let userData = userData else { return }
                    let ctx = Unmanaged<TTSStreamContext>.fromOpaque(userData).takeUnretainedValue()
                    let chunk = Data(bytes: audioPtr, count: audioSize)
                    ctx.onChunk(chunk)
                    ctx.totalData.append(chunk)
                },
                contextPtr
            )
        }

        let finalContext = Unmanaged<TTSStreamContext>.fromOpaque(contextPtr).takeRetainedValue()
        let totalAudioData = finalContext.totalData

        guard streamResult == RAC_SUCCESS else {
            throw SDKException.tts(.processingFailed, "Streaming synthesis failed: \(streamResult)")
        }

        let endTime = Date()
        let processingTime = endTime.timeIntervalSince(startTime)
        let numSamples = totalAudioData.count / 4
        let durationSec = Double(numSamples) / Double(options.sampleRate)

        let metadata = TTSSynthesisMetadata(
            voice: voiceId,
            language: options.language,
            processingTime: processingTime,
            characterCount: text.count
        )

        return TTSOutput(
            audioData: totalAudioData,
            format: options.audioFormat,
            duration: durationSec,
            phonemeTimestamps: nil,
            metadata: metadata
        )
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
