import CRunAnywhereCore  // C bridge for unified RunAnywhereCore xcframework
import Foundation
import RunAnywhere

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

        logger.info("Transcribing audio: \(audioData.count) bytes, input sample rate: \(options.sampleRate)Hz")

        // Convert audio data to float32 samples at 16kHz (STT model requirement)
        // Use the sample rate from options to determine if resampling is needed
        let samples = try convertToFloat32Samples(audioData: audioData, inputSampleRate: options.sampleRate)
        let sampleRate: Int32 = 16000

        var resultPtr: UnsafeMutablePointer<CChar>?

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
    ) async throws -> STTTranscriptionResult where S: AsyncSequence, S.Element == Data {
        guard isReady, let backend = backendHandle else {
            throw ONNXError.invalidHandle
        }

        guard supportsStreaming else {
            logger.warning("Stream transcribe not supported, using periodic batch transcription")
            return try await performBatchTranscription(
                audioStream: audioStream,
                options: options,
                onPartial: onPartial
            )
        }

        logger.info("Using streaming transcription")

        return try await performStreamingTranscription(
            backend: backend,
            audioStream: audioStream,
            options: options,
            onPartial: onPartial
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
            let hasWhisper = contents.contains(where: { $0.contains("whisper") })
            let hasEncoder = contents.contains(where: { $0.contains("encoder") })
            let hasDecoder = contents.contains(where: { $0.contains("decoder") })
            if hasWhisper || (hasEncoder && hasDecoder) {
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

    /// Convert Int16 PCM audio data to Float32 samples at 16kHz
    /// - Parameters:
    ///   - audioData: Raw Int16 PCM audio data
    ///   - inputSampleRate: Sample rate of the input audio (default: 48000Hz for device recordings)
    /// - Returns: Float32 samples resampled to 16kHz
    private func convertToFloat32Samples(audioData: Data, inputSampleRate: Int = 48000) throws -> [Float] {
        // Validate input parameters
        guard !audioData.isEmpty else {
            logger.error("Audio data is empty")
            throw ONNXError.invalidParameters
        }

        guard inputSampleRate > 0 else {
            logger.error("Invalid input sample rate: \(inputSampleRate)")
            throw ONNXError.invalidParameters
        }

        guard audioData.count.isMultiple(of: MemoryLayout<Int16>.size) else {
            logger.error("Audio data size (\(audioData.count) bytes) is not a multiple of Int16 size")
            throw ONNXError.invalidParameters
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

        logger.debug(
            "Converted \(int16Count) samples at \(inputSampleRate)Hz to " +
            "\(samples.count) samples at \(targetSampleRate)Hz (factor: \(downsampleFactor))"
        )
        return samples
    }

    /// Perform streaming transcription for models that support it
    private func performStreamingTranscription<S>(
        backend: ra_backend_handle,
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S: AsyncSequence, S.Element == Data {
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

        logger.info("Starting to process audio stream...")

        // Process audio chunks as they arrive
        lastResult = try await processAudioStream(
            audioStream: audioStream,
            backend: backend,
            stream: stream,
            options: options,
            onPartial: onPartial
        )

        // Signal input finished and get final result
        ra_stt_input_finished(backend, stream)
        lastResult = decodeFinalResult(backend: backend, stream: stream, currentResult: lastResult)

        logger.info("Final transcription: \(lastResult)")

        return STTTranscriptionResult(
            transcript: lastResult,
            confidence: 1.0,
            timestamps: nil,
            language: options.language,
            alternatives: nil
        )
    }

    /// Process audio stream chunks
    private func processAudioStream<S>(
        audioStream: S,
        backend: ra_backend_handle,
        stream: ra_stream_handle,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> String where S: AsyncSequence, S.Element == Data {
        let sampleRate: Int32 = 16000
        var result = ""
        var chunkCount = 0

        for try await audioChunk in audioStream {
            chunkCount += 1
            logger.debug("Received audio chunk #\(chunkCount), size: \(audioChunk.count) bytes")

            // Convert and feed audio
            let samples = try convertToFloat32Samples(audioData: audioChunk, inputSampleRate: options.sampleRate)
            let feedStatus = samples.withUnsafeBufferPointer { buffer in
                ra_stt_feed_audio(backend, stream, buffer.baseAddress, buffer.count, sampleRate)
            }

            guard feedStatus == RA_SUCCESS else {
                logger.error("Failed to feed audio: \(feedStatus.rawValue)")
                continue
            }

            // Decode if ready
            if ra_stt_is_ready(backend, stream) {
                if let newResult = decodePartialResult(backend: backend, stream: stream), newResult != result {
                    result = newResult
                    onPartial(newResult)
                    logger.debug("Partial result: \(newResult)")
                }
            }

            // Check for endpoint detection
            if ra_stt_is_endpoint(backend, stream) {
                logger.info("Endpoint detected")
                break
            }
        }

        return result
    }

    /// Perform batch transcription for models that don't support streaming
    private func performBatchTranscription<S>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S: AsyncSequence, S.Element == Data {
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

    /// Decode partial result from streaming session
    private func decodePartialResult(
        backend: ra_backend_handle,
        stream: ra_stream_handle
    ) -> String? {
        var resultPtr: UnsafeMutablePointer<CChar>?
        let decodeStatus = ra_stt_decode(backend, stream, &resultPtr)

        guard decodeStatus == RA_SUCCESS, let resultPtr = resultPtr else {
            return nil
        }

        defer { ra_free_string(resultPtr) }
        let partialJSON = String(cString: resultPtr)

        // Parse partial result
        guard let data = partialJSON.data(using: .utf8),
              let json = try? JSONDecoder().decode(PartialResult.self, from: data),
              !json.text.isEmpty else {
            return nil
        }

        return json.text
    }

    /// Decode final result from streaming session
    private func decodeFinalResult(
        backend: ra_backend_handle,
        stream: ra_stream_handle,
        currentResult: String
    ) -> String {
        var lastResult = currentResult

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

        return lastResult
    }
}

// MARK: - Supporting Types

private struct TranscriptionResult: Codable {
    let text: String
    let confidence: Double?
    let language: String?
    let metadata: TranscriptionMetadata?
}

private struct TranscriptionMetadata: Codable {
    let processingTimeMs: Double?
    let audioDurationMs: Double?
    let realTimeFactor: Double?

    enum CodingKeys: String, CodingKey {
        case processingTimeMs = "processing_time_ms"
        case audioDurationMs = "audio_duration_ms"
        case realTimeFactor = "real_time_factor"
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
