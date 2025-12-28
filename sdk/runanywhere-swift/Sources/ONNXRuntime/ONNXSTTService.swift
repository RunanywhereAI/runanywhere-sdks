//
//  ONNXSTTService.swift
//  ONNXRuntime
//
//  STT service implementation using runanywhere-commons ONNX backend.
//  This is a thin Swift wrapper around the rac_stt_onnx_* C APIs.
//

import CRABackendONNX
import CRACommons
import Foundation
import os
import RunAnywhere

/// ONNX-based STT service for speech-to-text transcription.
///
/// This service wraps the runanywhere-commons C++ ONNX backend,
/// providing Swift-friendly APIs for audio transcription.
///
/// ## Usage
///
/// ```swift
/// let service = ONNXSTTService()
/// try await service.initialize(modelPath: "/path/to/whisper-model")
///
/// let result = try await service.transcribe(
///     audioData: audioData,
///     options: STTOptions(sampleRate: 16000)
/// )
/// print("Transcribed: \(result.transcript)")
/// ```
public final class ONNXSTTService: STTService, @unchecked Sendable {

    // MARK: - Properties

    /// Native handle to the C++ ONNX STT service
    private var handle: rac_handle_t?

    /// Lock for thread-safe access to handle (async-safe)
    private let lock = OSAllocatedUnfairLock()

    /// Logger for this service
    private let logger = SDKLogger(category: "ONNXSTTService")

    /// Current model path
    private var _modelPath: String?

    // MARK: - STTService Protocol

    /// The inference framework (always ONNX)
    public var inferenceFramework: InferenceFramework { .onnx }

    /// Whether the service is ready for transcription
    public var isReady: Bool {
        lock.withLock {
            return handle != nil
        }
    }

    /// Current model identifier
    public var currentModel: String? {
        lock.withLock {
            return _modelPath
        }
    }

    /// ONNX STT supports streaming transcription
    public var supportsStreaming: Bool {
        lock.withLock {
            guard let handle = handle else { return false }
            return rac_stt_onnx_supports_streaming(handle) == RAC_TRUE
        }
    }

    // MARK: - Initialization

    public init() {
        logger.debug("ONNXSTTService instance created")
    }

    deinit {
        lock.withLock {
            if let handle = handle {
                rac_stt_onnx_destroy(handle)
            }
        }
    }

    /// Initialize the service with an optional model path.
    ///
    /// - Parameter modelPath: Path to an ONNX model directory. If nil, the service
    ///   is created but no model is loaded yet.
    public func initialize(modelPath: String?) async throws {
        logger.info("Initializing ONNXSTTService with model: \(modelPath ?? "none")")

        // Perform initialization under lock
        let initResult: Result<Void, Error> = lock.withLock {
            // Clean up existing handle if any
            if let existingHandle = handle {
                rac_stt_onnx_destroy(existingHandle)
                handle = nil
            }

            var newHandle: rac_handle_t?
            let result: rac_result_t

            if let path = modelPath {
                // Create config with default values
                var config = rac_stt_onnx_config_t()
                config.num_threads = 4

                // Create service with model
                result = path.withCString { pathPtr in
                    rac_stt_onnx_create(pathPtr, &config, &newHandle)
                }
                _modelPath = path
            } else {
                // Create service without model
                result = rac_stt_onnx_create(nil, nil, &newHandle)
            }

            if result == RAC_SUCCESS {
                handle = newHandle
                return .success(())
            } else {
                let error = CommonsErrorMapping.toSDKError(result)
                    ?? SDKError.stt(.initializationFailed, "Failed to initialize ONNX STT service")
                return .failure(error)
            }
        }

        // Handle result outside of lock
        switch initResult {
        case .success:
            logger.info("ONNXSTTService initialized successfully")
        case .failure(let error):
            logger.error("Failed to initialize ONNXSTTService: \(error)")
            throw error
        }
    }

    // MARK: - Transcription

    /// Transcribe audio data (batch mode).
    ///
    /// - Parameters:
    ///   - audioData: Audio data to transcribe
    ///   - options: Transcription options
    /// - Returns: Transcription result
    public func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult {
        logger.debug("Transcribe called with \(audioData.count) bytes")

        // Get handle under lock
        let lockedHandle = lock.withLock { handle }
        guard let handle = lockedHandle else {
            throw SDKError.stt(.serviceNotAvailable, "Service not initialized")
        }

        // Convert Swift options to C options
        var cOptions = rac_stt_options_t()
        cOptions.sample_rate = Int32(options.sampleRate)
        cOptions.enable_timestamps = options.enableTimestamps ? RAC_TRUE : RAC_FALSE

        // Convert audio data to float samples
        let floatSamples = audioData.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> [Float] in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            return int16Buffer.map { Float($0) / 32768.0 }
        }

        var cResult = rac_stt_result_t()

        // Set language - use withCString to ensure proper lifetime
        let transcribeResult = options.language.withCString { langPtr in
            cOptions.language = langPtr
            return floatSamples.withUnsafeBufferPointer { samplesBuffer in
                rac_stt_onnx_transcribe(
                    handle,
                    samplesBuffer.baseAddress,
                    samplesBuffer.count,
                    &cOptions,
                    &cResult
                )
            }
        }

        if transcribeResult == RAC_SUCCESS {
            // Extract transcription text
            var text = ""
            if let textPtr = cResult.text {
                text = String(cString: textPtr)
                // Free the C-allocated string
                textPtr.deallocate()
            }

            let result = STTTranscriptionResult(
                transcript: text,
                confidence: cResult.confidence > 0 ? cResult.confidence : nil,
                timestamps: nil,
                language: options.language.isEmpty ? nil : options.language,
                alternatives: nil
            )

            logger.debug("Transcription complete: \(text.prefix(50))...")
            return result
        } else {
            let error = CommonsErrorMapping.toSDKError(transcribeResult) ?? SDKError.stt(.generationFailed, "Transcription failed")
            logger.error("Transcription failed: \(error)")
            throw error
        }
    }

    /// Stream transcription for real-time processing.
    ///
    /// - Parameters:
    ///   - audioStream: Async stream of audio data chunks
    ///   - options: Transcription options
    ///   - onPartial: Callback for partial results
    /// - Returns: Final transcription result
    public func streamTranscribe<S: AsyncSequence>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S.Element == Data {
        logger.debug("Stream transcribe started")

        // Get handle under lock
        let lockedHandle = lock.withLock { handle }
        guard let serviceHandle = lockedHandle else {
            throw SDKError.stt(.serviceNotAvailable, "Service not initialized")
        }

        // Create streaming session
        var streamHandle: rac_handle_t?
        let createResult = rac_stt_onnx_create_stream(serviceHandle, &streamHandle)
        guard createResult == RAC_SUCCESS, let stream = streamHandle else {
            throw CommonsErrorMapping.toSDKError(createResult) ?? SDKError.stt(.streamingNotSupported, "Failed to create streaming session")
        }

        var fullText = ""

        do {
            for try await chunk in audioStream {
                // Convert audio data to float samples
                let floatSamples = chunk.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> [Float] in
                    let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
                    return int16Buffer.map { Float($0) / 32768.0 }
                }

                // Feed audio to stream
                let feedResult = floatSamples.withUnsafeBufferPointer { samplesBuffer in
                    rac_stt_onnx_feed_audio(
                        serviceHandle,
                        stream,
                        samplesBuffer.baseAddress,
                        samplesBuffer.count
                    )
                }

                guard feedResult == RAC_SUCCESS else {
                    continue
                }

                // Check if stream is ready for decoding
                if rac_stt_onnx_stream_is_ready(serviceHandle, stream) == RAC_TRUE {
                    var partialTextPtr: UnsafeMutablePointer<CChar>?
                    let decodeResult = rac_stt_onnx_decode_stream(serviceHandle, stream, &partialTextPtr)

                    if decodeResult == RAC_SUCCESS, let textPtr = partialTextPtr {
                        let partialText = String(cString: textPtr)
                        textPtr.deallocate()
                        if !partialText.isEmpty {
                            onPartial(partialText)
                            fullText = partialText
                        }
                    }
                }
            }

            // Signal end of input
            rac_stt_onnx_input_finished(serviceHandle, stream)

            // Get final result
            if rac_stt_onnx_stream_is_ready(serviceHandle, stream) == RAC_TRUE {
                var finalTextPtr: UnsafeMutablePointer<CChar>?
                let finalDecodeResult = rac_stt_onnx_decode_stream(serviceHandle, stream, &finalTextPtr)

                if finalDecodeResult == RAC_SUCCESS, let textPtr = finalTextPtr {
                    fullText = String(cString: textPtr)
                    textPtr.deallocate()
                }
            }

            // Cleanup stream
            rac_stt_onnx_destroy_stream(serviceHandle, stream)

        } catch {
            // Cancel streaming on error
            rac_stt_onnx_destroy_stream(serviceHandle, stream)
            throw error
        }

        logger.debug("Stream transcription complete")
        return STTTranscriptionResult(
            transcript: fullText,
            confidence: nil,
            timestamps: nil,
            language: options.language.isEmpty ? nil : options.language,
            alternatives: nil
        )
    }

    // MARK: - Lifecycle

    /// Clean up resources
    public func cleanup() async {
        // Use synchronous cleanup to avoid NSLock in async context issues
        cleanupSync()
    }

    /// Synchronous cleanup helper
    private func cleanupSync() {
        lock.withLock {
            if let handle = handle {
                rac_stt_onnx_destroy(handle)
                self.handle = nil
                logger.info("ONNXSTTService cleaned up")
            }
            _modelPath = nil
        }
    }
}
