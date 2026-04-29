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
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        let result = try await transcribe(audio: audioData, options: STTOptions())
        return result.text
    }

    // MARK: - Model Loading

    /// Unload the currently loaded STT model
    static func unloadSTTModel() async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        await CppBridge.STT.shared.unload()
    }

    /// Check if an STT model is loaded
    static var isSTTModelLoaded: Bool {
        get async {
            return await CppBridge.STT.shared.isLoaded
        }
    }

    /// Whether streaming transcription is currently active (CANONICAL_API §4).
    ///
    /// Forwards the underlying component's streaming-capable flag. A value of
    /// `true` indicates the model supports and is configured for streaming.
    static var isStreamingSTT: Bool {
        get async {
            guard await CppBridge.STT.shared.isLoaded else { return false }
            return await CppBridge.STT.shared.supportsStreaming
        }
    }

    // MARK: - Transcription

    /// Transcribe audio data to text with options (CANONICAL_API §4).
    ///
    /// Canonical two-argument overload: `transcribe(audio:options:)`.
    /// The previous name `transcribeWithOptions(_:options:)` has been removed.
    ///
    /// - Parameters:
    ///   - audio: Raw audio data
    ///   - options: Transcription options
    /// - Returns: Transcription output with text and metadata
    static func transcribe(
        audio audioData: Data,
        options: STTOptions
    ) async throws -> STTOutput {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.STT.shared.getHandle()

        guard await CppBridge.STT.shared.isLoaded else {
            throw SDKException.stt(.notInitialized, "STT model not loaded")
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
            throw SDKException.stt(.processingFailed, "Transcription failed: \(transcribeResult)")
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
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        guard let channelData = buffer.floatChannelData else {
            throw SDKException.stt(.emptyAudioBuffer, "Audio buffer has no channel data")
        }

        let frameLength = Int(buffer.frameLength)
        let audioData = Data(bytes: channelData[0], count: frameLength * MemoryLayout<Float>.size)

        let options: STTOptions
        if let language = language {
            options = STTOptions(language: language)
        } else {
            options = STTOptions()
        }

        return try await transcribe(audio: audioData, options: options)
    }

    // MARK: - Streaming Transcription (CANONICAL_API §4)

    /// Canonical stream-in / stream-out transcription (CANONICAL_API §4).
    ///
    /// Consumes an `AsyncStream<Data>` of PCM audio chunks and yields
    /// `RASTTPartialResult` events. Each partial result carries an
    /// incremental transcript and an `isFinal` flag; the stream closes after
    /// the final event or on error.
    ///
    /// - Parameters:
    ///   - audio: Source stream of raw PCM audio chunks.
    ///   - options: Transcription options (optional).
    /// - Returns: `AsyncStream<RASTTPartialResult>` of partial transcription events.
    static func transcribeStream(
        audio: AsyncStream<Data>,
        options: STTOptions = STTOptions()
    ) -> AsyncStream<RASTTPartialResult> {
        AsyncStream { continuation in
            Task {
                guard isInitialized else {
                    continuation.finish()
                    return
                }
                guard let handle = try? await CppBridge.STT.shared.getHandle(),
                      await CppBridge.STT.shared.isLoaded else {
                    continuation.finish()
                    return
                }
                for await chunk in audio {
                    if Task.isCancelled { break }
                    // Process each chunk as a discrete transcription unit and
                    // emit a partial result for every response token.
                    var sttResult = rac_stt_result_t()
                    let rc = options.withCOptions { cOptionsPtr in
                        chunk.withUnsafeBytes { audioPtr in
                            rac_stt_component_transcribe(
                                handle,
                                audioPtr.baseAddress,
                                chunk.count,
                                cOptionsPtr,
                                &sttResult
                            )
                        }
                    }
                    if rc == RAC_SUCCESS, let textPtr = sttResult.text {
                        let text = String(cString: textPtr)
                        var partial = RASTTPartialResult()
                        partial.text = text
                        partial.isFinal = false
                        continuation.yield(partial)
                    }
                    rac_stt_result_free(&sttResult)
                }
                // Emit terminal final event
                var finalPartial = RASTTPartialResult()
                finalPartial.isFinal = true
                continuation.yield(finalPartial)
                continuation.finish()
            }
        }
    }

    /// Transcribe audio with streaming callbacks (legacy form — prefer `transcribeStream(audio:options:)`)
    static func transcribeStream(
        audioData: Data,
        options: STTOptions = STTOptions(),
        onPartialResult: @escaping (STTTranscriptionResult) -> Void
    ) async throws -> STTOutput {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.STT.shared.getHandle()

        guard await CppBridge.STT.shared.isLoaded else {
            throw SDKException.stt(.notInitialized, "STT model not loaded")
        }

        guard await CppBridge.STT.shared.supportsStreaming else {
            throw SDKException.stt(.streamingNotSupported, "Model does not support streaming")
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
            throw SDKException.stt(.processingFailed, "Streaming transcription failed: \(result)")
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
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        let handle = try await CppBridge.STT.shared.getHandle()

        guard await CppBridge.STT.shared.isLoaded else {
            throw SDKException.stt(.notInitialized, "STT model not loaded")
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
            throw SDKException.stt(.processingFailed, "Streaming process failed: \(transcribeResult)")
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
