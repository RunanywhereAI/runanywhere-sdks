//
//  ONNXTTSService.swift
//  ONNXRuntime
//
//  TTS service implementation using runanywhere-commons ONNX backend.
//  This is a thin Swift wrapper around the rac_tts_onnx_* C APIs.
//

import CRABackendONNX
import CRACommons
import Foundation
import RunAnywhere

/// ONNX-based TTS service for text-to-speech synthesis.
///
/// This service wraps the runanywhere-commons C++ ONNX backend,
/// providing Swift-friendly APIs for speech synthesis using models like Piper.
///
/// ## Usage
///
/// ```swift
/// let service = ONNXTTSService(modelPath: "/path/to/piper-model")
/// try await service.initialize()
///
/// let audioData = try await service.synthesize(
///     text: "Hello, world!",
///     options: TTSOptions(rate: 1.0)
/// )
/// ```
public final class ONNXTTSService: TTSService, @unchecked Sendable {

    // MARK: - Properties

    /// Native handle to the C++ ONNX TTS service
    private var handle: rac_handle_t?

    /// Lock for thread-safe access to handle
    private let lock = NSLock()

    /// Logger for this service
    private let logger = SDKLogger(category: "ONNXTTSService")

    /// Model path for this service
    private let modelPath: String

    /// Whether synthesis is currently in progress
    private var _isSynthesizing = false

    // MARK: - TTSService Protocol

    /// The inference framework (always ONNX)
    public var inferenceFramework: InferenceFramework { .onnx }

    /// Whether synthesis is currently in progress
    public var isSynthesizing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSynthesizing
    }

    /// Available voices (model-dependent)
    public var availableVoices: [String] {
        // For ONNX/Piper models, the model itself is the "voice"
        return [modelPath]
    }

    // MARK: - Initialization

    public init(modelPath: String) {
        self.modelPath = modelPath
        logger.debug("ONNXTTSService instance created for model: \(modelPath)")
    }

    deinit {
        lock.lock()
        if let handle = handle {
            rac_tts_onnx_destroy(handle)
        }
        lock.unlock()
    }

    /// Initialize the service and load the model.
    public func initialize() async throws {
        logger.info("Initializing ONNXTTSService with model: \(modelPath)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()

            // Clean up existing handle if any
            if let existingHandle = handle {
                rac_tts_onnx_destroy(existingHandle)
                handle = nil
            }

            var newHandle: rac_handle_t?

            // Create config with default values
            var config = rac_tts_onnx_config_t()
            config.num_threads = 4

            // Create service with model
            let result = modelPath.withCString { pathPtr in
                rac_tts_onnx_create(pathPtr, &config, &newHandle)
            }

            if result == RAC_SUCCESS {
                handle = newHandle
                lock.unlock()
                logger.info("ONNXTTSService initialized successfully")
                continuation.resume()
            } else {
                lock.unlock()
                let error = CommonsErrorMapping.toSDKError(result) ?? SDKError.tts(.initializationFailed, "Failed to initialize ONNX TTS service")
                logger.error("Failed to initialize ONNXTTSService: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Synthesis

    /// Synthesize text to audio.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - options: Synthesis options
    /// - Returns: Audio data (16-bit PCM)
    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        logger.debug("Synthesize called for text: \(text.prefix(50))...")

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()

            guard let handle = handle else {
                lock.unlock()
                continuation.resume(throwing: SDKError.tts(.serviceNotAvailable, "Service not initialized"))
                return
            }

            _isSynthesizing = true
            lock.unlock()

            defer {
                lock.lock()
                _isSynthesizing = false
                lock.unlock()
            }

            // Convert Swift options to C options
            var cOptions = rac_tts_options_t()
            cOptions.sample_rate = Int32(options.sampleRate)
            cOptions.rate = options.rate

            var cResult = rac_tts_result_t()

            let synthesizeResult = text.withCString { textPtr in
                rac_tts_onnx_synthesize(handle, textPtr, &cOptions, &cResult)
            }

            if synthesizeResult == RAC_SUCCESS {
                // Convert audio data to Data
                var audioData = Data()
                if let dataPtr = cResult.audio_data, cResult.audio_size > 0 {
                    // Audio data is already in the correct format
                    audioData = Data(bytes: dataPtr, count: cResult.audio_size)
                    // Free the C-allocated data
                    dataPtr.deallocate()
                }

                logger.debug("Synthesis complete: \(cResult.audio_size) bytes")
                continuation.resume(returning: audioData)
            } else {
                let error = CommonsErrorMapping.toSDKError(synthesizeResult) ?? SDKError.tts(.generationFailed, "Synthesis failed")
                logger.error("Synthesis failed: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }

    /// Stream synthesis for long text.
    ///
    /// Note: ONNX TTS backend does not support streaming synthesis.
    /// This method synthesizes the full text and returns it as a single chunk.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize
    ///   - options: Synthesis options
    ///   - onChunk: Callback for each audio chunk
    public func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        logger.debug("Stream synthesize called for text: \(text.prefix(50))...")

        // ONNX TTS doesn't support streaming - synthesize full audio and return as single chunk
        let audioData = try await synthesize(text: text, options: options)
        onChunk(audioData)

        logger.debug("Stream synthesis complete (non-streaming fallback)")
    }

    // MARK: - Lifecycle

    /// Stop current synthesis
    public func stop() {
        lock.lock()
        if let handle = handle {
            rac_tts_onnx_stop(handle)
            logger.debug("Synthesis stopped")
        }
        _isSynthesizing = false
        lock.unlock()
    }

    /// Clean up resources
    public func cleanup() async {
        // Use synchronous cleanup to avoid NSLock in async context issues
        cleanupSync()
    }

    /// Synchronous cleanup helper
    private func cleanupSync() {
        lock.lock()
        if let handle = handle {
            rac_tts_onnx_destroy(handle)
            self.handle = nil
            logger.info("ONNXTTSService cleaned up")
        }
        lock.unlock()
    }
}
