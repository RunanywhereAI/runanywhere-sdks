import Foundation
import RunAnywhere
import CRunAnywhereCore  // C bridge for unified RunAnywhereCore xcframework

/// Error types for WhisperCPP operations
public enum WhisperCPPError: Error, LocalizedError {
    case initializationFailed
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case invalidHandle
    case cancelled
    case invalidParameters

    public var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "Failed to initialize WhisperCPP backend"
        case .modelLoadFailed(let path):
            return "Failed to load model: \(path)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .invalidHandle:
            return "Invalid backend handle"
        case .cancelled:
            return "Operation was cancelled"
        case .invalidParameters:
            return "Invalid parameters provided"
        }
    }

    static func from(code: Int32) -> WhisperCPPError {
        switch ra_result_code(rawValue: code) {
        case RA_ERROR_INIT_FAILED:
            return .initializationFailed
        case RA_ERROR_MODEL_LOAD_FAILED:
            return .modelLoadFailed("Unknown")
        case RA_ERROR_INFERENCE_FAILED:
            return .transcriptionFailed("Inference failed")
        case RA_ERROR_INVALID_HANDLE:
            return .invalidHandle
        case RA_ERROR_CANCELLED:
            return .cancelled
        default:
            return .transcriptionFailed("Unknown error: \(code)")
        }
    }
}

/// WhisperCPP implementation of STTService for speech-to-text
/// Uses the unified RunAnywhere backend API with whisper.cpp
public class WhisperCPPSTTService: STTService {
    private let logger = SDKLogger(category: "WhisperCPPSTTService")

    private var backendHandle: ra_backend_handle?
    private var streamHandle: ra_stream_handle?
    private var _isReady: Bool = false
    private var _currentModel: String?
    private var _supportsStreaming: Bool = false

    // MARK: - STTService Protocol

    public var isReady: Bool {
        return _isReady && backendHandle != nil
    }

    public var currentModel: String? {
        return _currentModel
    }

    /// Whether this service supports live/streaming transcription
    /// WhisperCPP supports streaming via state-based decoding
    public var supportsStreaming: Bool {
        return _supportsStreaming
    }

    public init() {
        logger.info("WhisperCPPSTTService initialized")
    }

    deinit {
        // Clean up stream
        if let stream = streamHandle, let backend = backendHandle {
            ra_stt_destroy_stream(backend, stream)
        }

        // Clean up backend
        if let backend = backendHandle {
            ra_destroy(backend)
        }

        logger.info("WhisperCPPSTTService deallocated")
    }

    public func initialize(modelPath: String?) async throws {
        logger.info("Initializing WhisperCPP Runtime with model: \(modelPath ?? "none")")

        // Create WhisperCPP backend
        backendHandle = ra_create_backend("whispercpp")
        guard backendHandle != nil else {
            logger.error("Failed to create WhisperCPP backend")
            throw WhisperCPPError.initializationFailed
        }

        // Initialize backend
        let initStatus = ra_initialize(backendHandle, nil)
        guard initStatus == RA_SUCCESS else {
            logger.error("Failed to initialize WhisperCPP backend: \(initStatus.rawValue)")
            ra_destroy(backendHandle)
            backendHandle = nil
            throw WhisperCPPError.from(code: Int32(initStatus.rawValue))
        }

        // Load STT model if path provided
        if let modelPath = modelPath {
            logger.info("Loading whisper model from: \(modelPath)")

            // Prepare model directory path
            var modelDir = modelPath
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false

            if fileManager.fileExists(atPath: modelPath, isDirectory: &isDirectory) && !isDirectory.boolValue {
                modelDir = (modelPath as NSString).deletingLastPathComponent
            }

            // Load STT model with whisper type
            let loadStatus = ra_stt_load_model(backendHandle, modelDir, "whisper", nil)
            guard loadStatus == RA_SUCCESS else {
                logger.error("Failed to load STT model: \(loadStatus.rawValue)")
                throw WhisperCPPError.modelLoadFailed(modelPath)
            }

            _currentModel = modelPath
            _supportsStreaming = ra_stt_supports_streaming(backendHandle)
            logger.info("STT model loaded, streaming supported: \(self.supportsStreaming)")
        }

        _isReady = true
        logger.info("WhisperCPP Runtime initialized successfully")
    }

    public func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult {
        guard isReady, let backend = backendHandle else {
            throw WhisperCPPError.invalidHandle
        }

        logger.info("Transcribing audio: \(audioData.count) bytes, input sample rate: \(options.sampleRate)Hz")

        // Convert audio data to float32 samples at 16kHz (STT model requirement)
        let samples = try convertToFloat32Samples(audioData: audioData, inputSampleRate: options.sampleRate)
        let sampleRate: Int32 = 16000

        var resultPtr: UnsafeMutablePointer<CChar>? = nil

        // Call STT transcribe
        let status = samples.withUnsafeBufferPointer { buffer in
            ra_stt_transcribe(
                backend,
                buffer.baseAddress,
                buffer.count,
                sampleRate,
                options.language,
                &resultPtr
            )
        }

        guard status == RA_SUCCESS, let resultPtr = resultPtr else {
            logger.error("Transcription failed with status: \(status.rawValue)")
            throw WhisperCPPError.from(code: Int32(status.rawValue))
        }

        defer {
            ra_free_string(resultPtr)
        }

        // Parse JSON result
        let resultJSON = String(cString: resultPtr)
        logger.debug("Transcription result JSON: \(resultJSON)")

        return try parseTranscriptionResult(json: resultJSON, language: options.language)
    }

    public func streamTranscribe<S>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S: AsyncSequence, S.Element == Data {
        guard isReady, let backend = backendHandle else {
            throw WhisperCPPError.invalidHandle
        }

        guard supportsStreaming else {
            logger.warning("Stream transcribe not supported, using periodic batch transcription")

            // For batch-only models, process audio in periodic chunks
            var allAudioData = Data()
            var accumulatedTranscript = ""
            var lastProcessedSize = 0
            let batchThreshold = 48000 * 2 * 3  // ~3 seconds of audio at 48kHz Int16 (288KB)

            for try await chunk in audioStream {
                allAudioData.append(chunk)

                // Process periodically when we have enough new audio
                let newDataSize = allAudioData.count - lastProcessedSize
                if newDataSize >= batchThreshold {
                    logger.info("Processing batch chunk: \(allAudioData.count) bytes total")

                    do {
                        let result = try await transcribe(audioData: allAudioData, options: options)
                        if !result.transcript.isEmpty {
                            accumulatedTranscript = result.transcript
                            onPartial(accumulatedTranscript)
                            logger.debug("Partial transcription: \(accumulatedTranscript)")
                        }
                    } catch {
                        logger.error("Periodic batch transcription failed: \(error.localizedDescription)")
                    }

                    lastProcessedSize = allAudioData.count
                }
            }

            // Final transcription with all audio
            logger.info("Final batch transcription: \(allAudioData.count) bytes")
            let result = try await transcribe(audioData: allAudioData, options: options)
            if !result.transcript.isEmpty {
                onPartial(result.transcript)
            }
            return result
        }

        logger.info("Using streaming transcription")

        // Create streaming session
        guard let stream = ra_stt_create_stream(backend, nil) else {
            logger.error("Failed to create STT stream")
            throw WhisperCPPError.initializationFailed
        }

        streamHandle = stream
        defer {
            ra_stt_destroy_stream(backend, stream)
            streamHandle = nil
        }

        let sampleRate: Int32 = 16000
        var lastResult = ""
        var chunkCount = 0

        logger.info("Starting to process audio stream...")

        // Process audio chunks as they arrive
        for try await audioChunk in audioStream {
            chunkCount += 1
            logger.debug("Received audio chunk #\(chunkCount), size: \(audioChunk.count) bytes")

            // Convert chunk to float32 samples (use sample rate from options)
            let samples = try convertToFloat32Samples(audioData: audioChunk, inputSampleRate: options.sampleRate)

            // Feed audio to stream
            let feedStatus = samples.withUnsafeBufferPointer { buffer in
                ra_stt_feed_audio(
                    backend,
                    stream,
                    buffer.baseAddress,
                    buffer.count,
                    sampleRate
                )
            }

            if feedStatus != RA_SUCCESS {
                logger.error("Failed to feed audio: \(feedStatus.rawValue)")
                continue
            }

            // Decode if ready
            if ra_stt_is_ready(backend, stream) {
                var resultPtr: UnsafeMutablePointer<CChar>?
                let decodeStatus = ra_stt_decode(backend, stream, &resultPtr)

                if decodeStatus == RA_SUCCESS, let resultPtr = resultPtr {
                    defer { ra_free_string(resultPtr) }
                    let partialJSON = String(cString: resultPtr)

                    // Parse partial result
                    if let data = partialJSON.data(using: .utf8),
                       let json = try? JSONDecoder().decode(PartialResult.self, from: data),
                       !json.text.isEmpty, json.text != lastResult {
                        lastResult = json.text
                        onPartial(json.text)
                        logger.debug("Partial result: \(json.text)")
                    }
                }
            }

            // Check for endpoint detection
            if ra_stt_is_endpoint(backend, stream) {
                logger.info("Endpoint detected")
                break
            }
        }

        // Signal input finished
        ra_stt_input_finished(backend, stream)

        // Final decode
        while ra_stt_is_ready(backend, stream) {
            var resultPtr: UnsafeMutablePointer<CChar>?
            if ra_stt_decode(backend, stream, &resultPtr) == RA_SUCCESS, let resultPtr = resultPtr {
                defer { ra_free_string(resultPtr) }
                let finalJSON = String(cString: resultPtr)
                if let data = finalJSON.data(using: .utf8),
                   let json = try? JSONDecoder().decode(PartialResult.self, from: data),
                   !json.text.isEmpty {
                    lastResult = json.text
                }
            }
        }

        logger.info("Final transcription: \(lastResult)")

        return STTTranscriptionResult(
            transcript: lastResult,
            confidence: 1.0,
            timestamps: nil,
            language: options.language,
            alternatives: nil
        )
    }

    public func cleanup() async {
        logger.info("Cleaning up WhisperCPP Runtime")

        // Clean up stream
        if let stream = streamHandle, let backend = backendHandle {
            ra_stt_destroy_stream(backend, stream)
            streamHandle = nil
        }

        // Clean up backend
        if let backend = backendHandle {
            ra_destroy(backend)
            backendHandle = nil
        }

        _isReady = false
        _currentModel = nil
        _supportsStreaming = false
    }

    // MARK: - Private Helpers

    private func parseTranscriptionResult(json: String, language: String?) throws -> STTTranscriptionResult {
        guard let jsonData = json.data(using: .utf8) else {
            throw WhisperCPPError.transcriptionFailed("Invalid JSON encoding")
        }

        let result = try JSONDecoder().decode(TranscriptionResult.self, from: jsonData)

        return STTTranscriptionResult(
            transcript: result.text,
            confidence: Float(result.confidence ?? 1.0),
            timestamps: nil,
            language: result.language ?? language,
            alternatives: nil
        )
    }

    /// Convert Int16 PCM audio data to Float32 samples at 16kHz
    /// - Parameters:
    ///   - audioData: Raw Int16 PCM audio data
    ///   - inputSampleRate: Sample rate of the input audio (default: 48000Hz for device recordings)
    /// - Returns: Float32 samples resampled to 16kHz
    private func convertToFloat32Samples(audioData: Data, inputSampleRate: Int = 48000) throws -> [Float] {
        // Validate input parameters
        guard !audioData.isEmpty else {
            logger.error("Audio data is empty")
            throw WhisperCPPError.invalidParameters
        }

        guard inputSampleRate > 0 else {
            logger.error("Invalid input sample rate: \(inputSampleRate)")
            throw WhisperCPPError.invalidParameters
        }

        guard audioData.count % MemoryLayout<Int16>.size == 0 else {
            logger.error("Audio data size (\(audioData.count) bytes) is not a multiple of Int16 size")
            throw WhisperCPPError.invalidParameters
        }

        let targetSampleRate = 16000
        let int16Count = audioData.count / MemoryLayout<Int16>.size

        // Calculate downsampling factor based on input sample rate
        // If input is already at 16kHz, no downsampling needed (factor = 1)
        // If input is at 48kHz, downsample by 3 (factor = 3)
        let downsampleFactor = max(1, inputSampleRate / targetSampleRate)

        var samples: [Float] = []
        samples.reserveCapacity(int16Count / downsampleFactor)

        audioData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let int16Buffer = bytes.bindMemory(to: Int16.self)

            if downsampleFactor == 1 {
                // No downsampling needed - input is already at target sample rate
                for i in 0..<int16Count {
                    let normalized = Float(int16Buffer[i]) / Float(Int16.max)
                    samples.append(normalized)
                }
            } else {
                // Downsample by taking every Nth sample
                var i = 0
                while i < int16Count {
                    let normalized = Float(int16Buffer[i]) / Float(Int16.max)
                    samples.append(normalized)
                    i += downsampleFactor
                }
            }
        }

        logger.debug("Converted \(int16Count) samples at \(inputSampleRate)Hz to \(samples.count) samples at \(targetSampleRate)Hz (factor: \(downsampleFactor))")
        return samples
    }
}

// MARK: - Supporting Types

private struct TranscriptionResult: Codable {
    let text: String
    let confidence: Double?
    let language: String?
    let metadata: Metadata?

    struct Metadata: Codable {
        let processingTimeMs: Double?
        let audioDurationMs: Double?
        let realTimeFactor: Double?

        enum CodingKeys: String, CodingKey {
            case processingTimeMs = "processing_time_ms"
            case audioDurationMs = "audio_duration_ms"
            case realTimeFactor = "real_time_factor"
        }
    }
}

private struct PartialResult: Codable {
    let text: String
    let isFinal: Bool?

    enum CodingKeys: String, CodingKey {
        case text
        case isFinal = "is_final"
    }
}
