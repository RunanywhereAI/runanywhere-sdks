//
//  RunAnywhere+STT.swift
//  RunAnywhere SDK
//
//  Public API for Speech-to-Text operations.
//  All transcription flows through C++ via CppBridge.STT / rac_stt_component,
//  which provides automatic telemetry for every backend (ONNX, WhisperKit, etc.).
//

@preconcurrency import AVFoundation
import CRACommons
import Foundation
import os

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

        await CppBridge.STT.shared.unload()
    }

    /// Check if an STT model is loaded
    static var isSTTModelLoaded: Bool {
        get async {
            return await CppBridge.STT.shared.isLoaded
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

        let handle = try await CppBridge.STT.shared.getHandle()

        guard await CppBridge.STT.shared.isLoaded else {
            throw SDKError.stt(.notInitialized, "STT model not loaded")
        }

        let modelId = await CppBridge.STT.shared.currentModelId ?? "unknown"
        let startTime = Date()

        let audioSizeBytes = audioData.count
        let audioLengthSec = estimateAudioLength(dataSize: audioSizeBytes)

        var sttResult = rac_stt_result_t()
        defer { rac_stt_result_free(&sttResult) }
        let transcribeResult = options.withCOptions { cOptionsPtr in
            audioData.withUnsafeBytes { audioPtr in
                rac_stt_component_transcribe(
                    handle,
                    audioPtr.baseAddress,
                    audioData.count,
                    cOptionsPtr,
                    &sttResult
                )
            }
        }

        guard transcribeResult == RAC_SUCCESS else {
            throw SDKError.stt(.processingFailed, "Transcription failed: \(transcribeResult)")
        }

        let endTime = Date()
        let processingTimeSec = endTime.timeIntervalSince(startTime)

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

        guard let channelData = buffer.floatChannelData else {
            throw SDKError.stt(.emptyAudioBuffer, "Audio buffer has no channel data")
        }

        let frameLength = Int(buffer.frameLength)
        let audioData = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)

        let options: STTOptions
        if let language = language {
            options = STTOptions(language: language)
        } else {
            options = STTOptions()
        }

        return try await transcribeWithOptions(audioData, options: options)
    }

    /// Start streaming transcription
    @available(*, deprecated, message: "Use transcribeStream(audioData:options:onPartialResult:) instead")
    static func startStreamingTranscription(
        options _: STTOptions = STTOptions(),
        onPartialResult _: @escaping (STTTranscriptionResult) -> Void,
        onFinalResult _: @escaping (STTOutput) -> Void,
        onError _: @escaping (Error) -> Void
    ) async throws {
        throw SDKError.stt(.streamingNotSupported, "Use transcribeStream(audioData:options:onPartialResult:) instead")
    }

    /// Transcribe audio with streaming callbacks
    static func transcribeStream(
        audioData: Data,
        options: STTOptions = STTOptions(),
        onPartialResult: @escaping (STTTranscriptionResult) -> Void
    ) async throws -> STTOutput {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.STT.shared.getHandle()

        guard await CppBridge.STT.shared.isLoaded else {
            throw SDKError.stt(.notInitialized, "STT model not loaded")
        }

        guard await CppBridge.STT.shared.supportsStreaming else {
            throw SDKError.stt(.streamingNotSupported, "Model does not support streaming")
        }

        let modelId = await CppBridge.STT.shared.currentModelId ?? "unknown"
        let startTime = Date()

        let context = STTStreamingContext(onPartialResult: onPartialResult)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()

        let result = options.withCOptions { cOptionsPtr in
            audioData.withUnsafeBytes { audioPtr in
                rac_stt_component_transcribe_stream(
                    handle,
                    audioPtr.baseAddress,
                    audioData.count,
                    cOptionsPtr,
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
        }

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
    static func processStreamingAudio(_ samples: [Float], options: STTOptions = STTOptions()) async throws {
        guard isSDKInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.STT.shared.getHandle()

        guard await CppBridge.STT.shared.isLoaded else {
            throw SDKError.stt(.notInitialized, "STT model not loaded")
        }

        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }

        var sttResult = rac_stt_result_t()
        defer { rac_stt_result_free(&sttResult) }
        let transcribeResult = options.withCOptions { cOptionsPtr in
            data.withUnsafeBytes { audioPtr in
                rac_stt_component_transcribe(
                    handle,
                    audioPtr.baseAddress,
                    data.count,
                    cOptionsPtr,
                    &sttResult
                )
            }
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

/// Context class for bridging C callbacks to Swift closures.
private final class STTStreamingContext: Sendable {
    let onPartialResult: @Sendable (STTTranscriptionResult) -> Void
    private let _finalText = OSAllocatedUnfairLock(initialState: "")

    var finalText: String {
        get { _finalText.withLock { $0 } }
        set { _finalText.withLock { $0 = newValue } }
    }

    init(onPartialResult: @Sendable @escaping (STTTranscriptionResult) -> Void) {
        self.onPartialResult = onPartialResult
    }
}
