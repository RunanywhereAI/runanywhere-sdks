//
//  RunAnywhere+STT.swift
//  RunAnywhere SDK
//
//  Public API for Speech-to-Text operations.
//  Calls C++ directly via HandleManager for all operations.
//  Events are emitted by C++ layer via CppEventBridge.
//

@preconcurrency import AVFoundation
import CRACommons
import Foundation

// MARK: - STT Operations

public extension RunAnywhere {

    // MARK: - Simple Transcription

    /// Simple voice transcription using default model
    /// - Parameter audioData: Audio data to transcribe
    /// - Returns: Transcribed text
    static func transcribe(_ audioData: Data) async throws -> String {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        let result = try await transcribeWithOptions(audioData, options: STTOptions())
        return result.text
    }

    // MARK: - Model Loading

    /// Unload the currently loaded STT model
    static func unloadSTTModel() async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        await HandleManager.shared.unloadSTT()
    }

    /// Check if an STT model is loaded
    static var isSTTModelLoaded: Bool {
        get async {
            await HandleManager.shared.isSTTLoaded
        }
    }

    // MARK: - Transcription

    /// Transcribe audio data to text (with options)
    /// - Parameters:
    ///   - audioData: Raw audio data
    ///   - options: Transcription options
    /// - Returns: Transcription output with text and metadata
    static func transcribeWithOptions(
        _ audioData: Data,
        options: STTOptions
    ) async throws -> STTOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Get handle from HandleManager
        let handle = try await HandleManager.shared.getSTTHandle()

        guard await HandleManager.shared.isSTTLoaded else {
            throw SDKError.stt(.notInitialized, "STT model not loaded")
        }

        let modelId = await HandleManager.shared.currentSTTModelId ?? "unknown"
        let startTime = Date()

        // Calculate audio metrics
        let audioSizeBytes = audioData.count
        let audioLengthSec = estimateAudioLength(dataSize: audioSizeBytes)

        // Build C options
        var cOptions = rac_stt_options_t()
        cOptions.language = (options.language as NSString).utf8String
        cOptions.sample_rate = Int32(options.sampleRate)

        // Transcribe (C++ emits events)
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
            throw SDKError.stt(.processingFailed, "Transcription failed: \(transcribeResult)")
        }

        let endTime = Date()
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

        // Create metadata
        let metadata = TranscriptionMetadata(
            modelId: modelId,
            processingTime: processingTimeSec,
            audioLength: audioLengthSec
        )

        return STTOutput(
            text: transcribedText,
            confidence: confidence,
            wordTimestamps: nil,
            detectedLanguage: detectedLanguage,
            alternatives: nil,
            metadata: metadata
        )
    }

    /// Transcribe audio buffer to text
    /// - Parameters:
    ///   - buffer: Audio buffer
    ///   - language: Optional language hint
    /// - Returns: Transcription output
    static func transcribeBuffer(
        _ buffer: AVAudioPCMBuffer,
        language: String? = nil
    ) async throws -> STTOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        // Convert AVAudioPCMBuffer to Data
        guard let channelData = buffer.floatChannelData else {
            throw SDKError.stt(.emptyAudioBuffer, "Audio buffer has no channel data")
        }

        let frameLength = Int(buffer.frameLength)
        let audioData = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)

        // Build options with language if provided
        let options: STTOptions
        if let language = language {
            options = STTOptions(language: language)
        } else {
            options = STTOptions()
        }

        return try await transcribeWithOptions(audioData, options: options)
    }

    /// Start streaming transcription
    /// - Parameters:
    ///   - options: Transcription options
    ///   - onPartialResult: Callback for partial transcription results
    ///   - onFinalResult: Callback for final transcription result
    ///   - onError: Callback for errors
    @available(*, deprecated, message: "Use transcribeStream(audioData:options:onPartialResult:) instead")
    static func startStreamingTranscription(
        options: STTOptions = STTOptions(),
        onPartialResult: @escaping (STTTranscriptionResult) -> Void,
        onFinalResult: @escaping (STTOutput) -> Void,
        onError: @escaping (Error) -> Void
    ) async throws {
        throw SDKError.stt(.streamingNotSupported, "Use transcribeStream(audioData:options:onPartialResult:) instead")
    }

    /// Transcribe audio with streaming callbacks
    /// - Parameters:
    ///   - audioData: Audio data to transcribe
    ///   - options: Transcription options
    ///   - onPartialResult: Callback for partial results
    /// - Returns: Final transcription output
    static func transcribeStream(
        audioData: Data,
        options: STTOptions = STTOptions(),
        onPartialResult: @escaping (STTTranscriptionResult) -> Void
    ) async throws -> STTOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await HandleManager.shared.getSTTHandle()

        guard await HandleManager.shared.isSTTLoaded else {
            throw SDKError.stt(.notInitialized, "STT model not loaded")
        }

        guard await HandleManager.shared.sttSupportsStreaming else {
            throw SDKError.stt(.streamingNotSupported, "Model does not support streaming")
        }

        let modelId = await HandleManager.shared.currentSTTModelId ?? "unknown"
        let startTime = Date()

        // Create context for callback bridging
        let context = STTStreamingContext(onPartialResult: onPartialResult)
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
                    let ctx = Unmanaged<STTStreamingContext>.fromOpaque(userData).takeUnretainedValue()

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
        let finalContext = Unmanaged<STTStreamingContext>.fromOpaque(contextPtr).takeRetainedValue()

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

        return STTOutput(
            text: finalContext.finalText,
            confidence: 0.0,
            wordTimestamps: nil,
            detectedLanguage: nil,
            alternatives: nil,
            metadata: metadata
        )
    }

    /// Process audio samples for streaming transcription
    /// - Parameter samples: Audio samples
    static func processStreamingAudio(_ samples: [Float]) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await HandleManager.shared.getSTTHandle()

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
    static func stopStreamingTranscription() async {
        // No-op - streaming is handled per-call
    }

    // MARK: - Private Helpers

    /// Estimate audio length from data size (assumes 16kHz mono 16-bit)
    private static func estimateAudioLength(dataSize: Int) -> Double {
        let bytesPerSample = 2  // 16-bit
        let sampleRate = 16000.0
        let samples = Double(dataSize) / Double(bytesPerSample)
        return samples / sampleRate
    }
}

// MARK: - Streaming Context Helper

/// Context class for bridging C callbacks to Swift closures
private final class STTStreamingContext: @unchecked Sendable {
    let onPartialResult: (STTTranscriptionResult) -> Void
    var finalText: String = ""

    init(onPartialResult: @escaping (STTTranscriptionResult) -> Void) {
        self.onPartialResult = onPartialResult
    }
}
