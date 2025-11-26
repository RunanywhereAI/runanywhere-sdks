import Foundation
import RunAnywhere
import CRunAnywhereONNX  // C wrapper module
import os

/// ONNX Runtime implementation of STTService for speech-to-text
public class ONNXSTTService: STTService {
    private let logger: Logger = Logger(subsystem: "com.runanywhere.onnx", category: "ONNXSTTService")

    private var handle: UnsafeMutableRawPointer?
    private var _isReady: Bool = false
    private var _currentModel: String?

    // Sherpa-ONNX handles for streaming STT
    private var sherpaRecognizer: UnsafeMutableRawPointer?
    private var sherpaStream: UnsafeMutableRawPointer?
    private var isSherpaModel: Bool = false

    // MARK: - STTService Protocol

    public var isReady: Bool {
        return _isReady && (handle != nil || sherpaRecognizer != nil)
    }

    public var currentModel: String? {
        return _currentModel
    }

    public init() {
        logger.info("ONNXSTTService initialized")
    }

    deinit {
        // Synchronously clean up to avoid retain cycle
        // Clean up sherpa-onnx resources
        if let stream = sherpaStream {
            ra_sherpa_destroy_stream(stream)
        }

        if let recognizer = sherpaRecognizer {
            ra_sherpa_destroy_recognizer(recognizer)
        }

        // Clean up standard ONNX handle
        if let handle = handle {
            ra_onnx_destroy(handle)
        }

        logger.info("ONNXSTTService deallocated")
    }

    public func initialize(modelPath: String?) async throws {
        logger.info("Initializing ONNX Runtime with model: \(modelPath ?? "none", privacy: .public)")

        // Check if this is a sherpa-onnx model
        if let modelPath = modelPath {
            isSherpaModel = detectSherpaModel(path: modelPath)

            if isSherpaModel {
                logger.info("Detected sherpa-onnx model, using streaming recognizer")
                try await initializeSherpaModel(path: modelPath)
            } else {
                logger.info("Using standard ONNX Runtime for model")
                try await initializeStandardModel(path: modelPath)
            }
        } else {
            // No model path provided, use standard ONNX runtime
            try await initializeStandardModel(path: nil)
        }

        _isReady = true
        logger.info("ONNX Runtime initialized successfully")
    }

    public func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult {
        guard isReady else {
            throw ONNXError.invalidHandle
        }

        logger.info("Transcribing audio: \(audioData.count) bytes")

        if isSherpaModel, let recognizer = sherpaRecognizer {
            return try await transcribeWithSherpa(audioData: audioData, recognizer: recognizer, options: options)
        } else if let handle = handle {
            return try await transcribeStandard(audioData: audioData, handle: handle, options: options)
        } else {
            throw ONNXError.invalidHandle
        }
    }

    public func streamTranscribe<S>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S : AsyncSequence, S.Element == Data {
        guard isReady else {
            throw ONNXError.invalidHandle
        }

        if isSherpaModel, let recognizer = sherpaRecognizer {
            // True streaming with sherpa-onnx
            logger.info("Using sherpa-onnx streaming transcription")
            return try await streamTranscribeWithSherpa(
                audioStream: audioStream,
                recognizer: recognizer,
                options: options,
                onPartial: onPartial
            )
        } else {
            // Fallback to batch processing for non-sherpa models
            logger.warning("Stream transcribe not available for non-sherpa models, using batch transcription")

            var allAudioData = Data()
            for try await chunk in audioStream {
                allAudioData.append(chunk)
            }

            return try await transcribe(audioData: allAudioData, options: options)
        }
    }

    public func cleanup() async {
        logger.info("Cleaning up ONNX Runtime")

        // Clean up sherpa-onnx resources
        if let stream = sherpaStream {
            ra_sherpa_destroy_stream(stream)
            sherpaStream = nil
        }

        if let recognizer = sherpaRecognizer {
            ra_sherpa_destroy_recognizer(recognizer)
            sherpaRecognizer = nil
        }

        // Clean up standard ONNX handle
        if let handle = handle {
            ra_onnx_destroy(handle)
            self.handle = nil
        }

        _isReady = false
        _currentModel = nil
        isSherpaModel = false
    }

    // MARK: - Private Helpers - Model Detection

    private func detectSherpaModel(path: String) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        logger.debug("Detecting model type for path: \(path)")

        // If path is a file (not directory), get the parent directory
        var modelDir = path
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue {
            // Path is a file, use its parent directory
            modelDir = (path as NSString).deletingLastPathComponent
            logger.debug("Path is a file, using parent directory: \(modelDir)")
        }

        // Check if parent directory exists and is a directory
        if !fileManager.fileExists(atPath: modelDir, isDirectory: &isDirectory) || !isDirectory.boolValue {
            logger.error("Model directory does not exist or is not a directory: \(modelDir)")
            return false
        }

        // Check if path is a directory (extracted sherpa model)
        logger.debug("Checking directory for sherpa-onnx model: \(modelDir)")

        // List directory contents for debugging
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: modelDir)
            logger.debug("Directory contents: \(contents.joined(separator: ", "))")
        } catch {
            logger.error("Failed to list directory contents: \(error)")
        }

        // Check for typical sherpa-onnx Zipformer files
        let encoderPath = (modelDir as NSString).appendingPathComponent("encoder-epoch-99-avg-1.onnx")
        let decoderPath = (modelDir as NSString).appendingPathComponent("decoder-epoch-99-avg-1.onnx")
        let tokensPath = (modelDir as NSString).appendingPathComponent("tokens.txt")

            if fileManager.fileExists(atPath: encoderPath) ||
               fileManager.fileExists(atPath: decoderPath) ||
               fileManager.fileExists(atPath: tokensPath) {
                logger.info("Detected Zipformer-style sherpa-onnx model")
                return true
            }

            // Check for whisper-style sherpa models (various naming patterns)
            let whisperPatterns = [
                "tiny.en-encoder.onnx",
                "tiny-encoder.onnx",
                "base.en-encoder.onnx",
                "base-encoder.onnx",
                "small.en-encoder.onnx",
                "small-encoder.onnx",
                "encoder.onnx"  // Generic encoder name
            ]

        for pattern in whisperPatterns {
            let whisperEncoder = (modelDir as NSString).appendingPathComponent(pattern)
            if fileManager.fileExists(atPath: whisperEncoder) {
                logger.info("Detected Whisper-style sherpa-onnx model with pattern: \(pattern)")
                return true
            }
        }

        // Check for any .onnx files - if directory contains multiple .onnx files, likely sherpa model
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: modelDir)
            let onnxFiles = contents.filter { $0.hasSuffix(".onnx") }

            // If there are multiple .onnx files or tokens.txt, treat as sherpa model
            if onnxFiles.count > 1 || contents.contains("tokens.txt") {
                logger.info("Found sherpa-indicative files, treating as sherpa model: \(onnxFiles.joined(separator: ", "))")
                return true
            }
        } catch {
            logger.error("Failed to check for .onnx files: \(error)")
        }

        // Check if path is a .tar.bz2 archive (sherpa model archive)
        if path.hasSuffix(".tar.bz2") {
            logger.info("Detected .tar.bz2 archive, treating as sherpa model")
            return true
        }

        logger.info("No sherpa-onnx model detected, using standard ONNX Runtime")
        return false
    }

    // MARK: - Standard ONNX Initialization

    private func initializeStandardModel(path: String?) async throws {
        // Create ONNX Runtime instance
        handle = ra_onnx_create()
        guard handle != nil else {
            logger.error("Failed to create ONNX Runtime handle")
            throw ONNXError.initializationFailed
        }

        // Initialize with default configuration
        let status = ra_onnx_initialize(handle, nil)
        guard status == 0 else { // RA_SUCCESS = 0
            logger.error("Failed to initialize ONNX Runtime: \(status)")
            ra_onnx_destroy(handle)
            handle = nil
            throw ONNXError.from(code: status)
        }

        // Load model if path provided
        if let modelPath = path {
            let loadStatus = ra_onnx_load_model(handle, modelPath)
            guard loadStatus == 0 else {
                logger.error("Failed to load model: \(loadStatus)")
                throw ONNXError.modelLoadFailed(modelPath)
            }
            _currentModel = modelPath
        }
    }

    // MARK: - Sherpa-ONNX Initialization

    private func initializeSherpaModel(path: String) async throws {
        var modelDir = path
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // If path is a file (not directory), get the parent directory
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue {
            // Path is a file, use its parent directory for sherpa-onnx
            modelDir = (path as NSString).deletingLastPathComponent
            logger.info("Path is a file, using parent directory for sherpa-onnx: \(modelDir)")
        }

        // If path is a .tar.bz2 archive, extract it first
        if path.hasSuffix(".tar.bz2") {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let pathNS = path as NSString
            let modelName = ((pathNS.deletingPathExtension as NSString).deletingPathExtension as NSString).lastPathComponent
            let extractPath = documentsPath.appendingPathComponent("sherpa-models/\(modelName)").path

            logger.info("Extracting sherpa model archive to: \(extractPath)")

            let status = ra_extract_tar_bz2(path, extractPath)
            guard status == 0 else {
                logger.error("Failed to extract model archive: \(status)")
                throw ONNXError.modelLoadFailed("Failed to extract archive")
            }

            modelDir = extractPath
        }

        // Create sherpa-onnx recognizer with auto-detected configuration
        logger.info("Creating sherpa-onnx recognizer from: \(modelDir)")

        // Auto-detect model files in the directory
        let contents = try fileManager.contentsOfDirectory(atPath: modelDir)
        logger.debug("Model directory contents: \(contents.joined(separator: ", "))")

        // Find encoder, decoder, and tokens files
        let encoderFile = contents.first { $0.contains("encoder") && $0.hasSuffix(".onnx") && !$0.contains("int8") }
        let decoderFile = contents.first { $0.contains("decoder") && $0.hasSuffix(".onnx") && !$0.contains("int8") }
        let tokensFile = contents.first { $0.contains("tokens") && $0.hasSuffix(".txt") }

        // Build JSON configuration
        var configDict: [String: Any] = [
            "num_threads": 2,
            "enable_endpoint_detection": true,
            "rule1_min_trailing_silence": 2.4,
            "rule2_min_trailing_silence": 1.2,
            "rule3_min_utterance_length": 20.0
        ]

        if let encoder = encoderFile, let decoder = decoderFile, let tokens = tokensFile {
            logger.info("Auto-detected model files - encoder: \(encoder), decoder: \(decoder), tokens: \(tokens)")
            configDict["encoder"] = (modelDir as NSString).appendingPathComponent(encoder)
            configDict["decoder"] = (modelDir as NSString).appendingPathComponent(decoder)
            configDict["tokens"] = (modelDir as NSString).appendingPathComponent(tokens)
        }

        // Convert to JSON string
        let jsonData = try JSONSerialization.data(withJSONObject: configDict, options: [])
        let configJSON = String(data: jsonData, encoding: .utf8)

        logger.debug("Sherpa config JSON: \(configJSON ?? "nil")")
        sherpaRecognizer = ra_sherpa_create_recognizer(modelDir, configJSON)

        guard sherpaRecognizer != nil else {
            logger.error("Failed to create sherpa-onnx recognizer")
            throw ONNXError.initializationFailed
        }

        _currentModel = path
        logger.info("Sherpa-ONNX recognizer created successfully")
    }

    // MARK: - Standard Transcription

    private func transcribeStandard(
        audioData: Data,
        handle: UnsafeMutableRawPointer,
        options: STTOptions
    ) async throws -> STTTranscriptionResult {
        // Prepare audio configuration
        var audioConfig = ra_audio_config(
            sample_rate: Int32(options.audioFormat.sampleRate),
            channels: 1,  // Mono
            bits_per_sample: 16,
            format: RA_AUDIO_FORMAT_PCM
        )

        var resultPtr: UnsafeMutablePointer<CChar>? = nil

        // Call C bridge function
        let status = audioData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            ra_onnx_transcribe(
                handle,
                bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                audioData.count,
                &audioConfig,
                options.language,
                &resultPtr
            )
        }

        guard status == 0, let resultPtr = resultPtr else {
            logger.error("Transcription failed with status: \(status)")
            throw ONNXError.from(code: status)
        }

        defer {
            ra_free_string(resultPtr)
        }

        // Parse JSON result
        let resultJSON = String(cString: resultPtr)
        logger.debug("Transcription result JSON: \(resultJSON)")

        guard let jsonData = resultJSON.data(using: .utf8) else {
            throw ONNXError.transcriptionFailed("Invalid JSON encoding")
        }

        let result = try JSONDecoder().decode(TranscriptionResult.self, from: jsonData)

        return STTTranscriptionResult(
            transcript: result.text,
            confidence: Float(result.confidence),
            timestamps: nil,
            language: result.language,
            alternatives: nil
        )
    }

    // MARK: - Sherpa-ONNX Transcription

    private func transcribeWithSherpa(
        audioData: Data,
        recognizer: UnsafeMutableRawPointer,
        options: STTOptions
    ) async throws -> STTTranscriptionResult {
        // Create a stream for this transcription
        guard let stream = ra_sherpa_create_stream(recognizer) else {
            logger.error("Failed to create sherpa stream")
            throw ONNXError.initializationFailed
        }

        defer {
            ra_sherpa_destroy_stream(stream)
        }

        // Convert audio data to float32 samples (also resamples from 48kHz to 16kHz)
        let samples = try convertToFloat32Samples(audioData: audioData)
        // sherpa-onnx expects 16kHz audio, we downsample from 48kHz in convertToFloat32Samples
        let sampleRate: Int32 = 16000

        // Feed audio to stream
        samples.withUnsafeBufferPointer { buffer in
            ra_sherpa_accept_waveform(stream, sampleRate, buffer.baseAddress, Int32(buffer.count))
        }

        // Signal input finished
        ra_sherpa_input_finished(stream)

        // Decode until ready
        while ra_sherpa_is_ready(recognizer, stream) != 0 {
            ra_sherpa_decode(recognizer, stream)
        }

        // Get final result
        let resultText = String(cString: ra_sherpa_get_result(recognizer, stream))

        logger.info("Sherpa transcription result: \(resultText)")

        return STTTranscriptionResult(
            transcript: resultText,
            confidence: 1.0,  // Sherpa doesn't provide confidence
            timestamps: nil,
            language: options.language,
            alternatives: nil
        )
    }

    // MARK: - Streaming Transcription with Sherpa

    private func streamTranscribeWithSherpa<S>(
        audioStream: S,
        recognizer: UnsafeMutableRawPointer,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S : AsyncSequence, S.Element == Data {
        // Create a stream for this transcription
        guard let stream = ra_sherpa_create_stream(recognizer) else {
            logger.error("Failed to create sherpa stream")
            throw ONNXError.initializationFailed
        }

        defer {
            ra_sherpa_destroy_stream(stream)
        }

        // sherpa-onnx expects 16kHz audio, we downsample from 48kHz in convertToFloat32Samples
        let sampleRate: Int32 = 16000
        var lastResult = ""
        var chunkCount = 0

        print("[SHERPA-SWIFT] Starting to process audio stream...")

        // Process audio chunks as they arrive
        for try await audioChunk in audioStream {
            chunkCount += 1
            print("[SHERPA-SWIFT] Received audio chunk #\(chunkCount), size: \(audioChunk.count) bytes")

            // Convert chunk to float32 samples (also resamples from 48kHz to 16kHz)
            let samples = try convertToFloat32Samples(audioData: audioChunk)
            print("[SHERPA-SWIFT] Converted to \(samples.count) float32 samples at 16kHz")

            // Feed audio to stream
            samples.withUnsafeBufferPointer { buffer in
                print("[SHERPA-SWIFT] Calling ra_sherpa_accept_waveform with \(buffer.count) samples at 16kHz")
                ra_sherpa_accept_waveform(stream, sampleRate, buffer.baseAddress, Int32(buffer.count))
                print("[SHERPA-SWIFT] ra_sherpa_accept_waveform returned")
            }

            // Decode if ready
            if ra_sherpa_is_ready(recognizer, stream) != 0 {
                ra_sherpa_decode(recognizer, stream)

                // Get partial result
                let partialText = String(cString: ra_sherpa_get_result(recognizer, stream))

                if partialText != lastResult && !partialText.isEmpty {
                    lastResult = partialText
                    onPartial(partialText)
                    logger.debug("Partial result: \(partialText)")
                }
            }

            // Check for endpoint detection
            if ra_sherpa_is_endpoint(recognizer, stream) != 0 {
                logger.info("Endpoint detected")
                break
            }
        }

        // Signal input finished
        ra_sherpa_input_finished(stream)

        // Final decode
        while ra_sherpa_is_ready(recognizer, stream) != 0 {
            ra_sherpa_decode(recognizer, stream)
        }

        // Get final result
        let finalText = String(cString: ra_sherpa_get_result(recognizer, stream))

        logger.info("Final sherpa transcription: \(finalText)")

        return STTTranscriptionResult(
            transcript: finalText.isEmpty ? lastResult : finalText,
            confidence: 1.0,
            timestamps: nil,
            language: options.language,
            alternatives: nil
        )
    }

    // MARK: - Audio Conversion

    private func convertToFloat32Samples(audioData: Data) throws -> [Float] {
        // Assuming input is Int16 PCM at 48kHz
        // Need to resample to 16kHz for sherpa-onnx (downsample by factor of 3)
        let int16Count = audioData.count / MemoryLayout<Int16>.size
        var samples: [Float] = []
        samples.reserveCapacity(int16Count / 3) // Downsample by 3x (48kHz -> 16kHz)

        audioData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let int16Buffer = bytes.bindMemory(to: Int16.self)

            // Simple downsampling: take every 3rd sample to go from 48kHz to 16kHz
            var i = 0
            while i < int16Count {
                // Normalize Int16 to Float32 range [-1, 1]
                let normalized = Float(int16Buffer[i]) / Float(Int16.max)
                samples.append(normalized)
                i += 3 // Skip 2 samples to downsample 48kHz -> 16kHz
            }
        }

        print("[AUDIO-CONVERT] Converted \(int16Count) samples at 48kHz to \(samples.count) samples at 16kHz")
        return samples
    }
}

// MARK: - Supporting Types

/// Internal structure matching C bridge JSON output
private struct TranscriptionResult: Codable {
    let text: String
    let confidence: Double
    let language: String
    let metadata: Metadata

    struct Metadata: Codable {
        let processingTimeMs: Double
        let audioDurationMs: Double
        let realTimeFactor: Double

        enum CodingKeys: String, CodingKey {
            case processingTimeMs = "processing_time_ms"
            case audioDurationMs = "audio_duration_ms"
            case realTimeFactor = "real_time_factor"
        }
    }
}

/// Metadata for transcription results
public struct TranscriptionMetadata {
    public let processingTimeMs: Double
    public let audioDurationMs: Double
    public let realTimeFactor: Double

    public init(processingTimeMs: Double, audioDurationMs: Double, realTimeFactor: Double) {
        self.processingTimeMs = processingTimeMs
        self.audioDurationMs = audioDurationMs
        self.realTimeFactor = realTimeFactor
    }
}
