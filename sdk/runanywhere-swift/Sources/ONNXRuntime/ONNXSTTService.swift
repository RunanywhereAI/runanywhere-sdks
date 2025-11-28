import Foundation
import RunAnywhere
import CRunAnywhereONNX  // C wrapper module

/// ONNX Runtime implementation of STTService for speech-to-text
/// Uses the unified RunAnywhere backend API
public class ONNXSTTService: STTService {
    private let logger = SDKLogger(category: "ONNXSTTService")

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
    /// ONNX Whisper models are offline/batch only, so this returns false
    public var supportsStreaming: Bool {
        return _supportsStreaming
    }

    public init() {
        logger.info("ONNXSTTService initialized")
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

        logger.info("ONNXSTTService deallocated")
    }

    public func initialize(modelPath: String?) async throws {
        logger.info("Initializing ONNX Runtime with model: \(modelPath ?? "none")")

        // Create ONNX backend
        backendHandle = ra_create_backend("onnx")
        guard backendHandle != nil else {
            logger.error("Failed to create ONNX backend")
            throw ONNXError.initializationFailed
        }

        // Initialize backend
        let initStatus = ra_initialize(backendHandle, nil)
        guard initStatus == RA_SUCCESS else {
            logger.error("Failed to initialize ONNX backend: \(initStatus.rawValue)")
            ra_destroy(backendHandle)
            backendHandle = nil
            throw ONNXError.from(code: Int32(initStatus.rawValue))
        }

        // Load STT model if path provided
        if let modelPath = modelPath {
            // Detect model type
            let modelType = detectModelType(path: modelPath)
            logger.info("Detected model type: \(modelType)")

            // Prepare model directory path
            var modelDir = modelPath
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false

            if fileManager.fileExists(atPath: modelPath, isDirectory: &isDirectory) && !isDirectory.boolValue {
                modelDir = (modelPath as NSString).deletingLastPathComponent
            }

            // Handle tar.bz2 archives using platform-native ArchiveUtility
            if modelPath.hasSuffix(".tar.bz2") {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let pathNS = modelPath as NSString
                let modelName = ((pathNS.deletingPathExtension as NSString).deletingPathExtension as NSString).lastPathComponent
                let extractURL = documentsPath.appendingPathComponent("sherpa-models/\(modelName)")

                logger.info("Extracting model archive to: \(extractURL.path)")

                do {
                    try ArchiveUtility.extractTarBz2Archive(
                        from: URL(fileURLWithPath: modelPath),
                        to: extractURL
                    )
                } catch {
                    logger.error("Failed to extract model archive: \(error.localizedDescription)")
                    throw ONNXError.modelLoadFailed("Failed to extract archive: \(error.localizedDescription)")
                }

                modelDir = extractURL.path
            }

            // Load STT model
            let loadStatus = ra_stt_load_model(backendHandle, modelDir, modelType, nil)
            guard loadStatus == RA_SUCCESS else {
                logger.error("Failed to load STT model: \(loadStatus.rawValue)")
                throw ONNXError.modelLoadFailed(modelPath)
            }

            _currentModel = modelPath
            _supportsStreaming = ra_stt_supports_streaming(backendHandle)
            logger.info("STT model loaded, streaming supported: \(self.supportsStreaming)")
        }

        _isReady = true
        logger.info("ONNX Runtime initialized successfully")
    }

    public func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult {
        guard isReady, let backend = backendHandle else {
            throw ONNXError.invalidHandle
        }

        logger.info("Transcribing audio: \(audioData.count) bytes")

        // Convert audio data to float32 samples
        let samples = try convertToFloat32Samples(audioData: audioData)
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
            throw ONNXError.from(code: Int32(status.rawValue))
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
    ) async throws -> STTTranscriptionResult where S : AsyncSequence, S.Element == Data {
        guard isReady, let backend = backendHandle else {
            throw ONNXError.invalidHandle
        }

        guard supportsStreaming else {
            logger.warning("Stream transcribe not supported, using periodic batch transcription")

            // For batch-only models, process audio in periodic chunks
            // This provides a more responsive "live" experience
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
            throw ONNXError.initializationFailed
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

            // Convert chunk to float32 samples
            let samples = try convertToFloat32Samples(audioData: audioChunk)

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
                var resultPtr: UnsafeMutablePointer<CChar>? = nil
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
            var resultPtr: UnsafeMutablePointer<CChar>? = nil
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
        logger.info("Cleaning up ONNX Runtime")

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

    private func detectModelType(path: String) -> String {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        var modelDir = path
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue {
            modelDir = (path as NSString).deletingLastPathComponent
        }

        // Check for model files
        if let contents = try? fileManager.contentsOfDirectory(atPath: modelDir) {
            // Zipformer detection
            if contents.contains(where: { $0.contains("encoder-epoch") && $0.hasSuffix(".onnx") }) {
                return "zipformer"
            }

            // Whisper detection
            if contents.contains(where: { $0.contains("whisper") || ($0.contains("encoder") && contents.contains(where: { $0.contains("decoder") })) }) {
                return "whisper"
            }

            // Paraformer detection
            if contents.contains(where: { $0.contains("paraformer") }) {
                return "paraformer"
            }
        }

        // Archive detection
        if path.hasSuffix(".tar.bz2") {
            if path.contains("zipformer") || path.contains("sherpa") {
                return "zipformer"
            }
        }

        // Default to whisper
        return "whisper"
    }

    private func parseTranscriptionResult(json: String, language: String?) throws -> STTTranscriptionResult {
        guard let jsonData = json.data(using: .utf8) else {
            throw ONNXError.transcriptionFailed("Invalid JSON encoding")
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

    private func convertToFloat32Samples(audioData: Data) throws -> [Float] {
        // Assuming input is Int16 PCM at 48kHz
        // Resample to 16kHz for STT (downsample by factor of 3)
        let int16Count = audioData.count / MemoryLayout<Int16>.size
        var samples: [Float] = []
        samples.reserveCapacity(int16Count / 3)

        audioData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let int16Buffer = bytes.bindMemory(to: Int16.self)

            // Simple downsampling: take every 3rd sample (48kHz -> 16kHz)
            var i = 0
            while i < int16Count {
                let normalized = Float(int16Buffer[i]) / Float(Int16.max)
                samples.append(normalized)
                i += 3
            }
        }

        logger.debug("Converted \(int16Count) samples at 48kHz to \(samples.count) samples at 16kHz")
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
