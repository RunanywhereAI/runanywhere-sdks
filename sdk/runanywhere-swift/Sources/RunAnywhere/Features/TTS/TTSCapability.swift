//
//  TTSCapability.swift
//  RunAnywhere SDK
//
//  Thin Swift wrapper over rac_tts_component_* C API.
//  All business logic is in the C++ layer; this is just a Swift interface.
//
//  ⚠️ WARNING: This is a direct wrapper. Do NOT add custom logic here.
//  The C++ layer (runanywhere-commons) is the source of truth.
//

@preconcurrency import AVFoundation
import CRACommons
import Foundation

/// Actor-based TTS capability that provides a simplified interface for text-to-speech.
/// This is a thin wrapper over the C++ rac_tts_component API.
public actor TTSCapability: ModelLoadableCapability {
    public typealias Configuration = TTSConfiguration

    // MARK: - State

    /// Handle to the C++ TTS component
    private var handle: rac_handle_t?

    /// Current configuration
    private var config: TTSConfiguration?

    /// Currently loaded voice
    private var loadedVoice: String?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "TTSCapability")
    private let analyticsService: TTSAnalyticsService
    private let audioPlayback = AudioPlaybackManager()

    // MARK: - Initialization

    public init(analyticsService: TTSAnalyticsService = TTSAnalyticsService()) {
        self.analyticsService = analyticsService
    }

    deinit {
        if let handle = handle {
            rac_tts_component_destroy(handle)
        }
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: TTSConfiguration) {
        self.config = config
    }

    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)

    public var isModelLoaded: Bool {
        get async {
            guard let handle = handle else { return false }
            return rac_tts_component_is_loaded(handle) == RAC_TRUE
        }
    }

    public var currentModelId: String? {
        get async { loadedVoice }
    }

    /// Whether the service supports streaming synthesis
    public var supportsStreaming: Bool {
        get async { true }  // C++ layer supports streaming
    }

    public func loadModel(_ modelId: String) async throws {
        try await loadVoice(modelId)
    }

    /// Load a voice for synthesis
    public func loadVoice(_ voiceId: String) async throws {
        // Create component if needed
        if handle == nil {
            var newHandle: rac_handle_t?
            let createResult = rac_tts_component_create(&newHandle)
            guard createResult == RAC_SUCCESS, let newTTSHandle = newHandle else {
                throw SDKError.tts(.modelLoadFailed, "Failed to create TTS component: \(createResult)")
            }
            handle = newTTSHandle
        }

        guard let handle = handle else {
            throw SDKError.tts(.modelLoadFailed, "No TTS component handle")
        }

        // Resolve voice ID to local file path
        let voicePath = try await resolveModelPath(voiceId)
        logger.info("Loading TTS voice from path: \(voicePath)")

        // Load voice using resolved path
        let result = voicePath.withCString { pathPtr in
            rac_tts_component_load_voice(handle, pathPtr)
        }

        guard result == RAC_SUCCESS else {
            throw SDKError.tts(.modelLoadFailed, "Failed to load voice: \(result)")
        }

        loadedVoice = voiceId
        logger.info("Voice loaded: \(voiceId)")
    }

    /// Resolve a model/voice ID to its local file path
    private func resolveModelPath(_ modelId: String) async throws -> String {
        let allModels = try await RunAnywhere.availableModels()

        guard let modelInfo = allModels.first(where: { $0.id == modelId }) else {
            throw SDKError.tts(.modelNotFound, "Voice '\(modelId)' not found in registry")
        }

        guard let localPath = modelInfo.localPath else {
            throw SDKError.tts(.modelNotFound, "Voice '\(modelId)' is not downloaded. Please download the model first.")
        }

        return localPath.path
    }

    public func unload() async throws {
        guard let handle = handle else { return }

        let result = rac_tts_component_cleanup(handle)
        if result != RAC_SUCCESS {
            logger.warning("Cleanup returned: \(result)")
        }

        loadedVoice = nil
        logger.info("Voice unloaded")
    }

    public func cleanup() async {
        if let handle = handle {
            rac_tts_component_cleanup(handle)
            rac_tts_component_destroy(handle)
        }
        handle = nil
        loadedVoice = nil
    }

    // MARK: - Synthesis

    /// Synthesize speech from text
    public func synthesize(
        _ text: String,
        options: TTSOptions = TTSOptions()
    ) async throws -> TTSOutput {
        guard let handle = handle else {
            throw SDKError.tts(.notInitialized, "TTS not initialized")
        }

        guard rac_tts_component_is_loaded(handle) == RAC_TRUE else {
            throw SDKError.tts(.notInitialized, "TTS voice not loaded")
        }

        let voiceId = loadedVoice ?? "unknown"

        logger.info("Synthesizing speech with voice: \(voiceId)")

        // Start analytics tracking
        let synthesisId = await analyticsService.startSynthesis(
            text: text,
            voice: voiceId,
            framework: .onnx
        )

        let startTime = Date()

        // Build C options
        var cOptions = rac_tts_options_t()
        cOptions.rate = options.rate
        cOptions.pitch = options.pitch
        cOptions.volume = options.volume
        cOptions.sample_rate = Int32(options.sampleRate)

        // Synthesize
        var ttsResult = rac_tts_result_t()
        let synthesizeResult = text.withCString { textPtr in
            rac_tts_component_synthesize(handle, textPtr, &cOptions, &ttsResult)
        }

        guard synthesizeResult == RAC_SUCCESS else {
            let error = SDKError.tts(.processingFailed, "Synthesis failed: \(synthesizeResult)")
            await analyticsService.trackSynthesisFailed(synthesisId: synthesisId, error: error)
            throw error
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
        // C++ returns Float32 (4 bytes per sample), so divide by 4
        let numSamples = audioData.count / 4
        let durationSec = Double(numSamples) / Double(sampleRate)
        let durationMs = durationSec * 1000

        // Complete analytics
        await analyticsService.completeSynthesis(
            synthesisId: synthesisId,
            audioDurationMs: durationMs,
            audioSizeBytes: audioData.count
        )

        logger.info("Synthesis completed: \(Int(durationMs))ms audio in \(Int(processingTime * 1000))ms")

        // Create metadata
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

    /// Synthesize speech with streaming output
    public func synthesizeStream(
        _ text: String,
        options: TTSOptions = TTSOptions(),
        onAudioChunk: @escaping (Data) -> Void
    ) async throws -> TTSOutput {
        guard let handle = handle else {
            throw SDKError.tts(.notInitialized, "TTS not initialized")
        }

        guard rac_tts_component_is_loaded(handle) == RAC_TRUE else {
            throw SDKError.tts(.notInitialized, "TTS voice not loaded")
        }

        let voiceId = loadedVoice ?? "unknown"

        logger.info("Starting streaming synthesis with voice: \(voiceId)")

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
        let sampleRate = options.sampleRate
        // C++ returns Float32 (4 bytes per sample), so divide by 4
        let numSamples = totalAudioData.count / 4
        let durationSec = Double(numSamples) / Double(sampleRate)

        logger.info("Streaming synthesis completed: \(Int(durationSec * 1000))ms audio")

        // Create metadata
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

    /// Stop current synthesis
    public func stop() async {
        guard let handle = handle else { return }
        rac_tts_component_stop(handle)
        logger.info("Synthesis stopped")
    }

    // MARK: - Analytics

    public func getAnalyticsMetrics() async -> TTSMetrics {
        await analyticsService.getMetrics()
    }

    // MARK: - Public API Compatibility

    /// Whether a voice is currently loaded
    public var isVoiceLoaded: Bool {
        get async { await isModelLoaded }
    }

    /// Current voice ID (alias for currentModelId)
    public var currentVoiceId: String? {
        get async { loadedVoice }
    }

    /// Available voices from the model registry
    /// Returns TTS model IDs that can be used for synthesis
    public var availableVoices: [String] {
        get async {
            // Query model registry for TTS models
            // Filter models that can support TTS (ONNX-based frameworks)
            let criteria = ModelCriteria(framework: .onnx)
            let ttsModels = ServiceContainer.shared.modelRegistry.filterModels(by: criteria)
            return ttsModels.map { $0.id }
        }
    }

    /// Whether TTS is currently speaking (not implemented in C++ layer)
    public var isSpeaking: Bool {
        get async { false }
    }

    /// Speak text using system audio (synthesize + play)
    public func speak(_ text: String, options: TTSOptions = TTSOptions()) async throws -> TTSSpeakResult {
        let output = try await synthesize(text, options: options)

        // Convert Float32 PCM to WAV format for AVAudioPlayer
        let wavData = convertFloat32PCMToWAV(
            pcmData: output.audioData,
            sampleRate: Int(options.sampleRate)
        )

        // Play the audio
        if !wavData.isEmpty {
            logger.info("Playing audio: \(wavData.count) bytes")
            try await audioPlayback.play(wavData)
        }

        return TTSSpeakResult(from: output)
    }

    /// Convert Float32 PCM samples to WAV format (Int16 PCM with header)
    ///
    /// C++ TTS returns Float32 samples in range [-1.0, 1.0], but AVAudioPlayer
    /// requires a complete audio file format (WAV) with headers.
    private func convertFloat32PCMToWAV(pcmData: Data, sampleRate: Int) -> Data {
        guard !pcmData.isEmpty else { return Data() }

        // Float32 is 4 bytes per sample
        let numSamples = pcmData.count / 4

        // Convert Float32 to Int16
        var int16Samples = [Int16](repeating: 0, count: numSamples)
        pcmData.withUnsafeBytes { rawBuffer in
            let floatBuffer = rawBuffer.bindMemory(to: Float.self)
            for i in 0..<numSamples {
                // Clamp to [-1.0, 1.0] and convert to Int16 range
                let sample = max(-1.0, min(1.0, floatBuffer[i]))
                int16Samples[i] = Int16(sample * 32767.0)
            }
        }

        // Build WAV header (44 bytes)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(numSamples * 2)  // Int16 = 2 bytes per sample
        let fileSize = dataSize + 36  // Header size minus 8 bytes for RIFF header

        var wavData = Data()

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // Chunk size
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // Audio format (PCM)
        wavData.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Audio data (Int16 samples)
        int16Samples.withUnsafeBufferPointer { buffer in
            wavData.append(UnsafeBufferPointer(start: UnsafeRawPointer(buffer.baseAddress)?.assumingMemoryBound(to: UInt8.self),
                                                count: numSamples * 2))
        }

        return wavData
    }

    /// Stop speaking
    public func stopSpeaking() async {
        audioPlayback.stop()
        await stop()
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
