//
//  STTCapability.swift
//  RunAnywhere SDK
//
//  Thin Swift wrapper over rac_stt_component_* C API.
//  All business logic is in the C++ layer; this is just a Swift interface.
//
//  ⚠️ WARNING: This is a direct wrapper. Do NOT add custom logic here.
//  The C++ layer (runanywhere-commons) is the source of truth.
//

@preconcurrency import AVFoundation
import CRACommons
import Foundation

/// Actor-based STT capability that provides a simplified interface for speech-to-text.
/// This is a thin wrapper over the C++ rac_stt_component API.
public actor STTCapability: ModelLoadableCapability {
    public typealias Configuration = STTConfiguration

    // MARK: - State

    /// Handle to the C++ STT component
    private var handle: rac_handle_t?

    /// Current configuration
    private var config: STTConfiguration?

    /// Currently loaded model ID
    private var loadedModelId: String?

    // MARK: - Dependencies

    private let logger = SDKLogger(category: "STTCapability")
    private let analyticsService: STTAnalyticsService

    // MARK: - Initialization

    public init(analyticsService: STTAnalyticsService = STTAnalyticsService()) {
        self.analyticsService = analyticsService
    }

    deinit {
        if let handle = handle {
            rac_stt_component_destroy(handle)
        }
    }

    // MARK: - Configuration (Capability Protocol)

    public func configure(_ config: STTConfiguration) {
        self.config = config
    }

    // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)

    public var isModelLoaded: Bool {
        get async {
            guard let handle = handle else { return false }
            return rac_stt_component_is_loaded(handle) == RAC_TRUE
        }
    }

    public var currentModelId: String? {
        get async { loadedModelId }
    }

    /// Whether the service supports streaming transcription
    public var supportsStreaming: Bool {
        get async { true }  // C++ layer supports streaming
    }

    public func loadModel(_ modelId: String) async throws {
        // Create component if needed
        if handle == nil {
            var newHandle: rac_handle_t?
            let createResult = rac_stt_component_create(&newHandle)
            guard createResult == RAC_SUCCESS, let newSTTHandle = newHandle else {
                throw SDKError.stt(.modelLoadFailed, "Failed to create STT component: \(createResult)")
            }
            handle = newSTTHandle
        }

        guard let handle = handle else {
            throw SDKError.stt(.modelLoadFailed, "No STT component handle")
        }

        // Resolve model ID to local file path
        let modelPath = try await resolveModelPath(modelId)
        logger.info("Loading STT model from path: \(modelPath)")

        // Load model using resolved path
        let result = modelPath.withCString { pathPtr in
            rac_stt_component_load_model(handle, pathPtr)
        }

        guard result == RAC_SUCCESS else {
            throw SDKError.stt(.modelLoadFailed, "Failed to load model: \(result)")
        }

        loadedModelId = modelId
        logger.info("Model loaded: \(modelId)")
    }

    /// Resolve a model ID to its local file path
    private func resolveModelPath(_ modelId: String) async throws -> String {
        let allModels = try await RunAnywhere.availableModels()

        guard let modelInfo = allModels.first(where: { $0.id == modelId }) else {
            throw SDKError.stt(.modelNotFound, "Model '\(modelId)' not found in registry")
        }

        guard let localPath = modelInfo.localPath else {
            throw SDKError.stt(.modelNotFound, "Model '\(modelId)' is not downloaded. Please download the model first.")
        }

        return localPath.path
    }

    public func unload() async throws {
        guard let handle = handle else { return }

        let result = rac_stt_component_cleanup(handle)
        if result != RAC_SUCCESS {
            logger.warning("Cleanup returned: \(result)")
        }

        loadedModelId = nil
        logger.info("Model unloaded")
    }

    public func cleanup() async {
        if let handle = handle {
            rac_stt_component_cleanup(handle)
            rac_stt_component_destroy(handle)
        }
        handle = nil
        loadedModelId = nil
    }

    // MARK: - Transcription

    /// Transcribe audio data
    public func transcribe(
        _ audioData: Data,
        options: STTOptions = STTOptions()
    ) async throws -> STTOutput {
        guard let handle = handle else {
            throw SDKError.stt(.notInitialized, "STT not initialized")
        }

        guard rac_stt_component_is_loaded(handle) == RAC_TRUE else {
            throw SDKError.stt(.notInitialized, "STT model not loaded")
        }

        let modelId = loadedModelId ?? "unknown"

        logger.info("Transcribing audio with model: \(modelId)")

        // Calculate audio metrics
        let audioSizeBytes = audioData.count
        let audioLengthSec = estimateAudioLength(dataSize: audioSizeBytes)
        let audioLengthMs = audioLengthSec * 1000

        // Start analytics tracking
        let transcriptionId = await analyticsService.startTranscription(
            modelId: modelId,
            audioLengthMs: audioLengthMs,
            audioSizeBytes: audioSizeBytes,
            language: options.language,
            isStreaming: false,
            framework: .onnx
        )

        let startTime = Date()

        // Build C options
        var cOptions = rac_stt_options_t()
        cOptions.language = (options.language as NSString).utf8String
        cOptions.sample_rate = Int32(options.sampleRate)

        // Transcribe
        var sttResult = rac_stt_result_t()
        let transcribeResult = audioData.withUnsafeBytes { audioPtr in
            rac_stt_component_transcribe(
                handle,
                audioPtr.baseAddress,
                audioData.count,
                &cOptions,
                &sttResult
            )
        }

        guard transcribeResult == RAC_SUCCESS else {
            let error = SDKError.stt(.processingFailed, "Transcription failed: \(transcribeResult)")
            await analyticsService.trackTranscriptionFailed(
                transcriptionId: transcriptionId,
                error: error
            )
            throw error
        }

        let endTime = Date()
        let latencyMs = endTime.timeIntervalSince(startTime) * 1000
        let processingTimeSec = endTime.timeIntervalSince(startTime)

        // Extract result
        let transcribedText: String
        if let textPtr = sttResult.text {
            transcribedText = String(cString: textPtr)
        } else {
            transcribedText = ""
        }
        let detectedLanguage: String?
        if let langPtr = sttResult.detected_language {
            detectedLanguage = String(cString: langPtr)
        } else {
            detectedLanguage = nil
        }
        let confidence = sttResult.confidence

        // Complete analytics
        await analyticsService.completeTranscription(
            transcriptionId: transcriptionId,
            text: transcribedText,
            confidence: confidence
        )

        let wordCount = transcribedText.split(separator: " ").count
        logger.info("Transcription completed: \(wordCount) words in \(Int(latencyMs))ms")

        // Create metadata
        let metadata = TranscriptionMetadata(
            modelId: modelId,
            processingTime: processingTimeSec,
            audioLength: audioLengthSec
        )

        return STTOutput(
            text: transcribedText,
            confidence: confidence,
            wordTimestamps: nil,  // Word timestamps not yet extracted from C API
            detectedLanguage: detectedLanguage,
            alternatives: nil,
            metadata: metadata
        )
    }

    /// Start streaming transcription with audio data
    /// Uses the C++ rac_stt_component_transcribe_stream API with callback bridging
    public func transcribeStream(
        audioData: Data,
        options: STTOptions = STTOptions(),
        onPartialResult: @escaping (STTTranscriptionResult) -> Void
    ) async throws -> STTOutput {
        guard let handle = handle else {
            throw SDKError.stt(.notInitialized, "STT not initialized")
        }

        guard rac_stt_component_is_loaded(handle) == RAC_TRUE else {
            throw SDKError.stt(.notInitialized, "STT model not loaded")
        }

        guard rac_stt_component_supports_streaming(handle) == RAC_TRUE else {
            throw SDKError.stt(.streamingNotSupported, "Model does not support streaming")
        }

        let modelId = loadedModelId ?? "unknown"
        logger.info("Starting streaming transcription with model: \(modelId)")

        let startTime = Date()

        // Create context for callback bridging
        let context = StreamingContext(onPartialResult: onPartialResult)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        // Build C options
        var cOptions = rac_stt_options_t()
        cOptions.language = (options.language as NSString).utf8String
        cOptions.sample_rate = Int32(options.sampleRate)

        // Stream transcription with callback
        let result = audioData.withUnsafeBytes { audioPtr in
            rac_stt_component_transcribe_stream(
                handle,
                audioPtr.baseAddress,
                audioData.count,
                &cOptions,
                { partialText, isFinal, userData in
                    guard let userData = userData else { return }
                    let ctx = Unmanaged<StreamingContext>.fromOpaque(userData).takeUnretainedValue()

                    let text = partialText.map { String(cString: $0) } ?? ""
                    let partialResult = STTTranscriptionResult(
                        transcript: text,
                        confidence: nil,
                        timestamps: nil,
                        language: nil,
                        alternatives: nil
                    )

                    ctx.onPartialResult(partialResult)

                    if isFinal == RAC_TRUE {
                        ctx.finalText = text
                    }
                },
                contextPtr
            )
        }

        // Release context
        let finalContext = Unmanaged<StreamingContext>.fromOpaque(contextPtr).takeRetainedValue()

        guard result == RAC_SUCCESS else {
            throw SDKError.stt(.processingFailed, "Streaming transcription failed: \(result)")
        }

        let endTime = Date()
        let processingTimeSec = endTime.timeIntervalSince(startTime)
        let audioLengthSec = estimateAudioLength(dataSize: audioData.count)

        let metadata = TranscriptionMetadata(
            modelId: modelId,
            processingTime: processingTimeSec,
            audioLength: audioLengthSec
        )

        logger.info("Streaming transcription completed in \(Int(processingTimeSec * 1000))ms")

        return STTOutput(
            text: finalContext.finalText,
            confidence: 0.0,
            wordTimestamps: nil,
            detectedLanguage: nil,
            alternatives: nil,
            metadata: metadata
        )
    }

    /// Legacy streaming interface - calls transcribeStream internally
    @available(*, deprecated, message: "Use transcribeStream(audioData:options:onPartialResult:) instead")
    public func startStreamingTranscription(
        options: STTOptions = STTOptions(),
        onPartialResult: @escaping (STTTranscriptionResult) -> Void,
        onFinalResult: @escaping (STTOutput) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        logger.warning("startStreamingTranscription is deprecated - use transcribeStream instead")
        throw SDKError.stt(.streamingNotSupported, "Use transcribeStream(audioData:options:onPartialResult:) instead")
    }

    /// Process audio samples for streaming transcription
    public func processStreamingAudio(_ samples: [Float]) async throws {
        guard let handle = handle else {
            throw SDKError.stt(.notInitialized, "STT not initialized")
        }

        // Process samples through C++ API
        var cOptions = rac_stt_options_t()
        cOptions.sample_rate = Int32(RAC_STT_DEFAULT_SAMPLE_RATE)

        let data = samples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        var sttResult = rac_stt_result_t()
        let transcribeResult = data.withUnsafeBytes { audioPtr in
            rac_stt_component_transcribe(
                handle,
                audioPtr.baseAddress,
                data.count,
                &cOptions,
                &sttResult
            )
        }

        if transcribeResult != RAC_SUCCESS {
            throw SDKError.stt(.processingFailed, "Streaming process failed: \(transcribeResult)")
        }
    }

    /// Stop streaming transcription
    public func stopStreamingTranscription() async {
        logger.info("Streaming transcription stopped")
    }

    // MARK: - Analytics

    public func getAnalyticsMetrics() async -> STTMetrics {
        await analyticsService.getMetrics()
    }

    // MARK: - Private Methods

    /// Estimate audio length from data size (assumes 16kHz mono 16-bit)
    private func estimateAudioLength(dataSize: Int) -> Double {
        let bytesPerSample = 2  // 16-bit
        let sampleRate = 16000.0
        let samples = Double(dataSize) / Double(bytesPerSample)
        return samples / sampleRate
    }
}

// MARK: - Streaming Context Helper

/// Context class for bridging C callbacks to Swift closures
/// This is used internally by STTCapability for streaming transcription
private final class StreamingContext: @unchecked Sendable {
    let onPartialResult: (STTTranscriptionResult) -> Void
    var finalText: String = ""

    init(onPartialResult: @escaping (STTTranscriptionResult) -> Void) {
        self.onPartialResult = onPartialResult
    }
}
