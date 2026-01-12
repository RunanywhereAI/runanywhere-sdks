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
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Resolve voice ID to local file path
        let allModels = try await availableModels()
        guard let modelInfo = allModels.first(where: { $0.id == voiceId }) else {
            throw SDKError.tts(.modelNotFound, "Voice '\(voiceId)' not found in registry")
        }
        guard let localPath = modelInfo.localPath else {
            throw SDKError.tts(.modelNotFound, "Voice '\(voiceId)' is not downloaded")
        }

        try await CppBridge.TTS.shared.loadVoice(localPath.path, voiceId: voiceId, voiceName: modelInfo.name)
    }

    /// Unload the currently loaded TTS voice
    static func unloadTTSVoice() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        await CppBridge.TTS.shared.unload()
    }

    /// Check if a TTS voice is loaded
    static var isTTSVoiceLoaded: Bool {
        get async {
            await CppBridge.TTS.shared.isLoaded
        }
    }

    /// Get available TTS voices
    static var availableTTSVoices: [String] {
        get async {
            let allModels = await CppBridge.ModelRegistry.shared.getByFrameworks([.onnx])
            let ttsModels = allModels.filter { $0.category == .speechSynthesis }
            return ttsModels.map { $0.id }
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
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.TTS.shared.getHandle()

        guard await CppBridge.TTS.shared.isLoaded else {
            throw SDKError.tts(.notInitialized, "TTS voice not loaded")
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
        let synthesizeResult = text.withCString { textPtr in
            rac_tts_component_synthesize(handle, textPtr, &cOptions, &ttsResult)
        }

        guard synthesizeResult == RAC_SUCCESS else {
            throw SDKError.tts(.processingFailed, "Synthesis failed: \(synthesizeResult)")
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

    /// Stream synthesis for long text
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
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.TTS.shared.getHandle()

        guard await CppBridge.TTS.shared.isLoaded else {
            throw SDKError.tts(.notInitialized, "TTS voice not loaded")
        }

        let voiceId = await CppBridge.TTS.shared.currentVoiceId ?? "unknown"
        let startTime = Date()
        var totalAudioData = Data()

        // Build C options
        var cOptions = rac_tts_options_t()
        cOptions.rate = options.rate
        cOptions.pitch = options.pitch
        cOptions.volume = options.volume
        cOptions.sample_rate = Int32(options.sampleRate)

        // Create callback context
        let context = TTSStreamContext(onChunk: onAudioChunk, totalData: &totalAudioData)
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
                    ctx.totalData.pointee.append(chunk)
                },
                contextPtr
            )
        }

        Unmanaged<TTSStreamContext>.fromOpaque(contextPtr).release()

        guard streamResult == RAC_SUCCESS else {
            throw SDKError.tts(.processingFailed, "Streaming synthesis failed: \(streamResult)")
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
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
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
            throw SDKError.tts(.processingFailed, "Failed to convert PCM to WAV: \(result)")
        }

        let wavData = Data(bytes: ptr, count: wavSize)
        rac_free(ptr)

        return wavData
    }
}

// MARK: - Streaming Context

private final class TTSStreamContext: @unchecked Sendable {
    let onChunk: (Data) -> Void
    var totalData: UnsafeMutablePointer<Data>

    init(onChunk: @escaping (Data) -> Void, totalData: UnsafeMutablePointer<Data>) {
        self.onChunk = onChunk
        self.totalData = totalData
    }
}
