import CRunAnywhereCore  // C bridge for unified RunAnywhereCore xcframework
import Foundation
import RunAnywhere

/// ONNX Runtime implementation of TTSService for text-to-speech
/// Uses the unified RunAnywhere backend API with Sherpa-ONNX VITS/Piper models
public final class ONNXTTSService: NSObject, TTSService, @unchecked Sendable {
    private let logger = SDKLogger(category: "ONNXTTSService")

    private var backendHandle: ra_backend_handle?
    private var modelPath: String?
    private var _isSynthesizing: Bool = false
    private var _isReady: Bool = false

    // MARK: - Initialization

    public override init() {
        super.init()
        logger.info("ONNXTTSService initialized")
    }

    /// Initialize with a specific model directory path
    public init(modelPath: String) {
        self.modelPath = modelPath
        super.init()
        logger.info("ONNXTTSService initialized with model path: \(modelPath)")
    }

    deinit {
        // Clean up backend
        if let backend = backendHandle {
            ra_tts_unload_model(backend)
            ra_destroy(backend)
        }
        logger.info("ONNXTTSService deallocated")
    }

    // MARK: - TTSService Protocol

    public func initialize() async throws {
        guard let modelPath = modelPath else {
            logger.error("No model path provided for ONNX TTS")
            throw SDKError.modelNotFound("No model path provided for ONNX TTS")
        }

        logger.info("Initializing ONNX TTS with model at: \(modelPath)")
        verifyModelExists(at: modelPath)
        logAvailableBackends()

        try createAndInitializeBackend()

        let modelDir = try prepareModelDirectory(from: modelPath)
        try loadTTSModel(from: modelDir, originalPath: modelPath)

        _isReady = true
        logger.info("ONNX TTS initialized successfully")
    }

    public func synthesize(text: String, options: TTSOptions) async throws -> Data {
        guard _isReady, let backend = backendHandle else {
            throw SDKError.componentNotInitialized("ONNX TTS not initialized")
        }

        _isSynthesizing = true
        defer { _isSynthesizing = false }

        logger.info("Synthesizing: \"\(text.prefix(50))...\"")

        // Prepare output variables
        var samples: UnsafeMutablePointer<Float>?
        var numSamples: Int = 0
        var sampleRate: Int32 = 0

        // Parse voice ID (speaker ID for multi-speaker models, default to 0)
        let voiceId = options.voice ?? "0"

        // Speed: options.rate where 1.0 = normal
        let speed = options.rate

        // Pitch shift
        let pitch = options.pitch

        // Generate speech using the C API
        let result = ra_tts_synthesize(
            backend,
            text,
            voiceId,
            speed,
            pitch,
            &samples,
            &numSamples,
            &sampleRate
        )

        guard result == RA_SUCCESS, let samples = samples, numSamples > 0 else {
            logger.error("Failed to synthesize speech. Error code: \(result.rawValue)")
            throw SDKError.generationFailed("Failed to synthesize speech from ONNX TTS")
        }

        defer {
            ra_free_audio(samples)
        }

        logger.info("Generated \(numSamples) samples at \(sampleRate) Hz")

        // Convert float samples to audio data (16-bit PCM WAV)
        let audioData = convertToPCMData(samples: samples, count: numSamples, sampleRate: Int(sampleRate))

        logger.info("Audio data size: \(audioData.count) bytes")

        return audioData
    }

    public func synthesizeStream(
        text: String,
        options: TTSOptions,
        onChunk: @escaping (Data) -> Void
    ) async throws {
        // VITS/Piper doesn't natively support streaming, so we synthesize the whole thing
        // and return it as a single chunk
        let audioData = try await synthesize(text: text, options: options)
        onChunk(audioData)
    }

    public func stop() {
        _isSynthesizing = false
        if let backend = backendHandle {
            ra_tts_cancel(backend)
        }
    }

    public var isSynthesizing: Bool {
        _isSynthesizing
    }

    public var availableVoices: [String] {
        guard _isReady, let backend = backendHandle else { return [] }

        // Get available voices from the backend
        if let voicesPtr = ra_tts_get_voices(backend) {
            defer { ra_free_string(voicesPtr) }
            let voicesJSON = String(cString: voicesPtr)

            // Try to parse as JSON array
            if let data = voicesJSON.data(using: .utf8),
               let voices = try? JSONDecoder().decode([String].self, from: data) {
                return voices
            }

            // If not JSON, return as single voice
            return [voicesJSON]
        }

        // Default: return speaker ID 0 for single-speaker models
        return ["0"]
    }

    public func cleanup() async {
        logger.info("Cleaning up ONNX TTS")

        if let backend = backendHandle {
            ra_tts_unload_model(backend)
            ra_destroy(backend)
            backendHandle = nil
        }

        _isReady = false
        _isSynthesizing = false
    }

    // MARK: - Private Helpers - Initialization

    private func verifyModelExists(at path: String) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            logger.info("Model file exists at path")
        } else {
            logger.error("Model file does NOT exist at path: \(path)")
        }
    }

    private func logAvailableBackends() {
        var backendCount: Int32 = 0
        if let backends = ra_get_available_backends(&backendCount) {
            var availableBackends: [String] = []
            for i in 0..<Int(backendCount) {
                if let backendName = backends[i] {
                    availableBackends.append(String(cString: backendName))
                }
            }
            logger.info("Available backends (\(backendCount)): \(availableBackends)")
        } else {
            logger.warning("ra_get_available_backends returned nil")
        }
    }

    private func createAndInitializeBackend() throws {
        // Create ONNX backend
        logger.info("Creating ONNX backend via ra_create_backend('onnx')...")
        backendHandle = ra_create_backend("onnx")
        if let handle = backendHandle {
            logger.info("Backend handle created successfully: \(handle)")
        } else {
            // Get the last error message
            if let lastError = ra_get_last_error() {
                let errorStr = String(cString: lastError)
                logger.error("ra_create_backend('onnx') returned nil - Last error: \(errorStr)")
            } else {
                logger.error("ra_create_backend('onnx') returned nil - No error message available")
            }
            throw ONNXError.initializationFailed
        }

        // Initialize backend
        logger.info("Initializing backend via ra_initialize()...")
        let initStatus = ra_initialize(backendHandle, nil)
        logger.info("ra_initialize() returned status: \(initStatus.rawValue) (RA_SUCCESS=\(RA_SUCCESS.rawValue))")
        guard initStatus == RA_SUCCESS else {
            if let lastError = ra_get_last_error() {
                let errorStr = String(cString: lastError)
                let statusMessage = "Failed to initialize ONNX backend: status=\(initStatus.rawValue), error: \(errorStr)"
                logger.error(statusMessage)
            } else {
                logger.error("Failed to initialize ONNX backend: status=\(initStatus.rawValue)")
            }
            ra_destroy(backendHandle)
            backendHandle = nil
            throw ONNXError.from(code: Int32(initStatus.rawValue))
        }
        logger.info("Backend initialized successfully")
    }

    private func prepareModelDirectory(from modelPath: String) throws -> String {
        let fileManager = FileManager.default
        var modelDir = modelPath
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: modelPath, isDirectory: &isDirectory) && !isDirectory.boolValue {
            modelDir = (modelPath as NSString).deletingLastPathComponent
        }

        // Handle tar.bz2 archives using platform-native ArchiveUtility
        if modelPath.hasSuffix(".tar.bz2") {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let pathNS = modelPath as NSString
            let baseName = (pathNS.deletingPathExtension as NSString).deletingPathExtension as NSString
            let modelName = baseName.lastPathComponent
            let extractURL = documentsPath.appendingPathComponent("sherpa-models/tts/\(modelName)")

            logger.info("Extracting TTS model archive to: \(extractURL.path)")

            // Check if already extracted
            if !fileManager.fileExists(atPath: extractURL.path) {
                do {
                    try ArchiveUtility.extractTarBz2Archive(
                        from: URL(fileURLWithPath: modelPath),
                        to: extractURL
                    )
                } catch {
                    logger.error("Failed to extract TTS model archive: \(error.localizedDescription)")
                    throw ONNXError.modelLoadFailed("Failed to extract archive: \(error.localizedDescription)")
                }
            }

            modelDir = extractURL.path
        }

        return modelDir
    }

    private func loadTTSModel(from modelDir: String, originalPath: String) throws {
        logger.info("Loading TTS model from directory: \(modelDir)")
        logger.info("Model type: vits")

        // List directory contents for debugging
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(atPath: modelDir) {
            logger.info("Model directory contents: \(contents)")
        } else {
            logger.warning("Could not list model directory contents")
        }

        let loadStatus = ra_tts_load_model(backendHandle, modelDir, "vits", nil)
        logger.info("ra_tts_load_model() returned status: \(loadStatus.rawValue)")
        guard loadStatus == RA_SUCCESS else {
            if let lastError = ra_get_last_error() {
                let errorStr = String(cString: lastError)
                let statusMessage = "Failed to load TTS model: status=\(loadStatus.rawValue), " +
                                  "modelDir=\(modelDir), error: \(errorStr)"
                logger.error(statusMessage)
            } else {
                logger.error("Failed to load TTS model: status=\(loadStatus.rawValue), modelDir=\(modelDir)")
            }
            throw ONNXError.modelLoadFailed(originalPath)
        }
    }

    // MARK: - Private Helpers - Audio Conversion

    /// Convert float samples [-1, 1] to 16-bit PCM WAV data
    private func convertToPCMData(samples: UnsafePointer<Float>, count: Int, sampleRate: Int) -> Data {
        // Create WAV header + PCM data
        let bytesPerSample = 2  // 16-bit
        let numChannels = 1
        let dataSize = count * bytesPerSample
        let fileSize = 44 + dataSize  // WAV header is 44 bytes

        var data = Data(capacity: fileSize)

        // WAV Header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // Format chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // Chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // Audio format (PCM)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Array($0) })  // Channels
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })  // Sample rate
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * numChannels * bytesPerSample).littleEndian) { Array($0) })  // Byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels * bytesPerSample).littleEndian) { Array($0) })  // Block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bytesPerSample * 8).littleEndian) { Array($0) })  // Bits per sample

        // Data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Convert float samples to 16-bit PCM
        for i in 0..<count {
            let sample = samples[i]
            // Clamp to [-1, 1] and convert to Int16
            let clampedSample = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clampedSample * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }

        return data
    }
}
