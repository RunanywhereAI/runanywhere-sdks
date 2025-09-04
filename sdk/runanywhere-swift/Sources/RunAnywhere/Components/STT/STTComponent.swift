import Foundation
@preconcurrency import AVFoundation

// MARK: - STT Options

/// Options for speech-to-text transcription
public struct STTOptions: Sendable {
    public let language: String
    public let detectLanguage: Bool
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let maxSpeakers: Int?
    public let enableTimestamps: Bool
    public let vocabularyFilter: [String]
    public let audioFormat: AudioFormat

    public init(
        language: String = "en",
        detectLanguage: Bool = false,
        enablePunctuation: Bool = true,
        enableDiarization: Bool = false,
        maxSpeakers: Int? = nil,
        enableTimestamps: Bool = true,
        vocabularyFilter: [String] = [],
        audioFormat: AudioFormat = .pcm
    ) {
        self.language = language
        self.detectLanguage = detectLanguage
        self.enablePunctuation = enablePunctuation
        self.enableDiarization = enableDiarization
        self.maxSpeakers = maxSpeakers
        self.enableTimestamps = enableTimestamps
        self.vocabularyFilter = vocabularyFilter
        self.audioFormat = audioFormat
    }
}

// MARK: - STT Result

/// Result from speech-to-text transcription
public struct STTResult: Sendable {
    public let text: String
    public let segments: [STTSegment]
    public let language: String?
    public let confidence: Float
    public let duration: TimeInterval
    public let alternatives: [STTAlternative]

    public init(
        text: String,
        segments: [STTSegment] = [],
        language: String? = nil,
        confidence: Float = 1.0,
        duration: TimeInterval = 0,
        alternatives: [STTAlternative] = []
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.confidence = confidence
        self.duration = duration
        self.alternatives = alternatives
    }
}

/// A segment of transcribed text with timing
public struct STTSegment: Sendable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float
    public let speaker: Int?

    public init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float = 1.0,
        speaker: Int? = nil
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speaker = speaker
    }
}

/// Alternative transcription result
public struct STTAlternative: Sendable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

/// Errors for STT services
public enum STTError: LocalizedError {
    case serviceNotInitialized
    case transcriptionFailed(Error)
    case streamingNotSupported
    case languageNotSupported(String)
    case modelNotFound(String)
    case audioFormatNotSupported
    case insufficientAudioData
    case noVoiceServiceAvailable
    case audioSessionNotConfigured
    case audioSessionActivationFailed
    case microphonePermissionDenied

    public var errorDescription: String? {
        switch self {
        case .serviceNotInitialized:
            return "STT service is not initialized"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .streamingNotSupported:
            return "Streaming transcription is not supported"
        case .languageNotSupported(let language):
            return "Language not supported: \(language)"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .audioFormatNotSupported:
            return "Audio format is not supported"
        case .insufficientAudioData:
            return "Insufficient audio data for transcription"
        case .noVoiceServiceAvailable:
            return "No STT service available for transcription"
        case .audioSessionNotConfigured:
            return "Audio session is not configured"
        case .audioSessionActivationFailed:
            return "Failed to activate audio session"
        case .microphonePermissionDenied:
            return "Microphone permission was denied"
        }
    }
}

/// Enum to specify preferred audio format for the service
public enum STTServiceAudioFormat {
    case data       // Service prefers raw Data
    case floatArray // Service prefers Float array samples
}

// MARK: - STT Service Protocol

/// Protocol for speech-to-text services
public protocol STTService: AnyObject {
    /// Initialize the service with optional model path
    func initialize(modelPath: String?) async throws

    /// Transcribe audio data
    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult

    /// Stream transcription for real-time processing
    func streamTranscribe<S: AsyncSequence>(
        audioStream: S,
        options: STTOptions,
        onPartial: @escaping (String) -> Void
    ) async throws -> STTTranscriptionResult where S.Element == Data

    /// Check if service is ready
    var isReady: Bool { get }

    /// Get current model identifier
    var currentModel: String? { get }

    /// Cleanup resources
    func cleanup() async
}

// MARK: - STT Configuration

/// Configuration for STT component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
public struct STTConfiguration: ComponentConfiguration, ComponentInitParameters {
    /// Component type
    public var componentType: SDKComponent { .stt }

    /// Model ID
    public let modelId: String?

    // Model parameters
    public let language: String
    public let sampleRate: Int
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let vocabularyList: [String]
    public let maxAlternatives: Int
    public let enableTimestamps: Bool
    public let useGPUIfAvailable: Bool

    public init(
        modelId: String? = nil,
        language: String = "en-US",
        sampleRate: Int = 16000,
        enablePunctuation: Bool = true,
        enableDiarization: Bool = false,
        vocabularyList: [String] = [],
        maxAlternatives: Int = 1,
        enableTimestamps: Bool = true,
        useGPUIfAvailable: Bool = true
    ) {
        self.modelId = modelId
        self.language = language
        self.sampleRate = sampleRate
        self.enablePunctuation = enablePunctuation
        self.enableDiarization = enableDiarization
        self.vocabularyList = vocabularyList
        self.maxAlternatives = maxAlternatives
        self.enableTimestamps = enableTimestamps
        self.useGPUIfAvailable = useGPUIfAvailable
    }

    public func validate() throws {
        guard sampleRate > 0 && sampleRate <= 48000 else {
            throw SDKError.validationFailed("Sample rate must be between 1 and 48000 Hz")
        }
        guard maxAlternatives > 0 && maxAlternatives <= 10 else {
            throw SDKError.validationFailed("Max alternatives must be between 1 and 10")
        }
    }
}

// MARK: - STT Input/Output Models

/// Input for Speech-to-Text (conforms to ComponentInput protocol)
public struct STTInput: ComponentInput {
    /// Audio data to transcribe
    public let audioData: Data

    /// Audio buffer (alternative to data)
    public let audioBuffer: AVAudioPCMBuffer?

    /// Audio format information
    public let format: AudioFormat

    /// Language code override (e.g., "en-US")
    public let language: String?

    /// Optional VAD output for context
    public let vadOutput: VADOutput?

    /// Custom options override
    public let options: STTOptions?

    public init(
        audioData: Data,
        format: AudioFormat = .wav,
        language: String? = nil,
        vadOutput: VADOutput? = nil,
        options: STTOptions? = nil
    ) {
        self.audioData = audioData
        self.audioBuffer = nil
        self.format = format
        self.language = language
        self.vadOutput = vadOutput
        self.options = options
    }

    public init(
        audioBuffer: AVAudioPCMBuffer,
        format: AudioFormat = .pcm,
        language: String? = nil,
        vadOutput: VADOutput? = nil,
        options: STTOptions? = nil
    ) {
        self.audioData = Data()
        self.audioBuffer = audioBuffer
        self.format = format
        self.language = language
        self.vadOutput = vadOutput
        self.options = options
    }

    public func validate() throws {
        if audioData.isEmpty && audioBuffer == nil {
            throw SDKError.validationFailed("STTInput must contain either audioData or audioBuffer")
        }
    }
}

/// Output from Speech-to-Text (conforms to ComponentOutput protocol)
public struct STTOutput: ComponentOutput {
    /// Transcribed text
    public let text: String

    /// Confidence score (0.0 to 1.0)
    public let confidence: Float

    /// Word-level timestamps if available
    public let wordTimestamps: [WordTimestamp]?

    /// Detected language if auto-detected
    public let detectedLanguage: String?

    /// Alternative transcriptions if available
    public let alternatives: [TranscriptionAlternative]?

    /// Processing metadata
    public let metadata: TranscriptionMetadata

    /// Timestamp (required by ComponentOutput)
    public let timestamp: Date

    public init(
        text: String,
        confidence: Float,
        wordTimestamps: [WordTimestamp]? = nil,
        detectedLanguage: String? = nil,
        alternatives: [TranscriptionAlternative]? = nil,
        metadata: TranscriptionMetadata,
        timestamp: Date = Date()
    ) {
        self.text = text
        self.confidence = confidence
        self.wordTimestamps = wordTimestamps
        self.detectedLanguage = detectedLanguage
        self.alternatives = alternatives
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

/// Transcription metadata
public struct TranscriptionMetadata: Sendable {
    public let modelId: String
    public let processingTime: TimeInterval
    public let audioLength: TimeInterval
    public let realTimeFactor: Double // Processing time / audio length

    public init(
        modelId: String,
        processingTime: TimeInterval,
        audioLength: TimeInterval
    ) {
        self.modelId = modelId
        self.processingTime = processingTime
        self.audioLength = audioLength
        self.realTimeFactor = audioLength > 0 ? processingTime / audioLength : 0
    }
}

/// Word timestamp information
public struct WordTimestamp: Sendable {
    public let word: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float

    public init(word: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}

/// Alternative transcription
public struct TranscriptionAlternative: Sendable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

/// Transcription result from service
public struct STTTranscriptionResult: Sendable {
    public let transcript: String
    public let confidence: Float?
    public let timestamps: [TimestampInfo]?
    public let language: String?
    public let alternatives: [AlternativeTranscription]?

    public init(
        transcript: String,
        confidence: Float? = nil,
        timestamps: [TimestampInfo]? = nil,
        language: String? = nil,
        alternatives: [AlternativeTranscription]? = nil
    ) {
        self.transcript = transcript
        self.confidence = confidence
        self.timestamps = timestamps
        self.language = language
        self.alternatives = alternatives
    }

    public struct TimestampInfo: Sendable {
        public let word: String
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let confidence: Float?

        public init(word: String, startTime: TimeInterval, endTime: TimeInterval, confidence: Float? = nil) {
            self.word = word
            self.startTime = startTime
            self.endTime = endTime
            self.confidence = confidence
        }
    }

    public struct AlternativeTranscription: Sendable {
        public let transcript: String
        public let confidence: Float

        public init(transcript: String, confidence: Float) {
            self.transcript = transcript
            self.confidence = confidence
        }
    }
}

// MARK: - STT Framework Adapter Protocol

/// Protocol for STT framework adapters
public protocol STTFrameworkAdapter: ComponentAdapter where ServiceType: STTService {
    /// Create an STT service for the given configuration
    func createSTTService(configuration: STTConfiguration) async throws -> ServiceType
}

// MARK: - STT Service Registration

/// Protocol for registering external STT implementations
public protocol STTServiceProvider {
    /// Create an STT service for the given configuration
    func createSTTService(configuration: STTConfiguration) async throws -> STTService

    /// Check if this provider can handle the given model
    func canHandle(modelId: String?) -> Bool

    /// Provider name for identification
    var name: String { get }
}

// MARK: - STT Service Wrapper

/// Wrapper class to allow protocol-based STT service to work with BaseComponent
public final class STTServiceWrapper: ServiceWrapper {
    public typealias ServiceProtocol = any STTService
    public var wrappedService: (any STTService)?

    public init(_ service: (any STTService)? = nil) {
        self.wrappedService = service
    }
}

// MARK: - STT Component

/// Speech-to-Text component following the clean architecture
@MainActor
public final class STTComponent: BaseComponent<STTServiceWrapper>, @unchecked Sendable {

    // MARK: - Properties

    public override class var componentType: SDKComponent { .stt }

    private let sttConfiguration: STTConfiguration
    private var isModelLoaded = false
    private var modelPath: String?

    // MARK: - Initialization

    public init(configuration: STTConfiguration) {
        self.sttConfiguration = configuration
        super.init(configuration: configuration)
    }

    // MARK: - Service Creation

    public override func createService() async throws -> STTServiceWrapper {
        // Try to get a registered STT provider from central registry
        guard let provider = ModuleRegistry.shared.sttProvider(for: sttConfiguration.modelId) else {
            throw SDKError.componentNotInitialized(
                "No STT service provider registered. Please register WhisperKitServiceProvider.register()"
            )
        }

        // Check if model needs downloading
        if let modelId = sttConfiguration.modelId {
            modelPath = modelId
            // Provider should handle model management
        }

        // Create service through provider
        let sttService = try await provider.createSTTService(configuration: sttConfiguration)

        // Wrap the service
        let wrapper = STTServiceWrapper(sttService)

        // Service is already initialized by the provider
        isModelLoaded = true

        return wrapper
    }

    public override func performCleanup() async throws {
        await service?.wrappedService?.cleanup()
        isModelLoaded = false
        modelPath = nil
    }

    // MARK: - Model Management

    private func downloadModel(modelId: String) async throws {
        // Emit download started event
        eventBus.publish(ComponentInitializationEvent.componentDownloadStarted(
            component: Self.componentType,
            modelId: modelId
        ))

        // Simulate download with progress
        for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
            eventBus.publish(ComponentInitializationEvent.componentDownloadProgress(
                component: Self.componentType,
                modelId: modelId,
                progress: progress
            ))
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 second
        }

        // Emit download completed event
        eventBus.publish(ComponentInitializationEvent.componentDownloadCompleted(
            component: Self.componentType,
            modelId: modelId
        ))
    }

    // MARK: - Helper Methods

    private var sttService: (any STTService)? {
        return service?.wrappedService
    }

    // MARK: - Public API

    /// Transcribe audio data
    public func transcribe(_ audioData: Data, format: AudioFormat = .wav, language: String? = nil) async throws -> STTOutput {
        try ensureReady()

        let input = STTInput(
            audioData: audioData,
            format: format,
            language: language
        )
        return try await process(input)
    }

    /// Transcribe audio buffer
    public func transcribe(_ audioBuffer: AVAudioPCMBuffer, language: String? = nil) async throws -> STTOutput {
        try ensureReady()

        let input = STTInput(
            audioBuffer: audioBuffer,
            format: .pcm,
            language: language
        )
        return try await process(input)
    }

    /// Transcribe with VAD context
    public func transcribeWithVAD(_ audioData: Data, format: AudioFormat = .wav, vadOutput: VADOutput) async throws -> STTOutput {
        try ensureReady()

        let input = STTInput(
            audioData: audioData,
            format: format,
            vadOutput: vadOutput
        )
        return try await process(input)
    }

    /// Process STT input
    public func process(_ input: STTInput) async throws -> STTOutput {
        try ensureReady()

        guard let service = sttService else {
            throw SDKError.componentNotReady("STT service not available")
        }

        // Validate input
        try input.validate()

        // Create options from input or use defaults
        let options = input.options ?? STTOptions(
            language: input.language ?? sttConfiguration.language,
            detectLanguage: input.language == nil,
            enablePunctuation: sttConfiguration.enablePunctuation,
            enableDiarization: sttConfiguration.enableDiarization,
            maxSpeakers: nil,
            enableTimestamps: sttConfiguration.enableTimestamps,
            vocabularyFilter: sttConfiguration.vocabularyList,
            audioFormat: input.format
        )

        // Get audio data
        let audioData: Data
        if !input.audioData.isEmpty {
            audioData = input.audioData
        } else if let buffer = input.audioBuffer {
            audioData = convertBufferToData(buffer)
        } else {
            throw SDKError.validationFailed("No audio data provided")
        }

        // Track processing time
        let startTime = Date()

        // Perform transcription
        let result = try await service.transcribe(audioData: audioData, options: options)

        let processingTime = Date().timeIntervalSince(startTime)

        // Convert to strongly typed output
        let wordTimestamps = result.timestamps?.map { timestamp in
            WordTimestamp(
                word: timestamp.word,
                startTime: timestamp.startTime,
                endTime: timestamp.endTime,
                confidence: timestamp.confidence ?? 0.9
            )
        }

        let alternatives = result.alternatives?.map { alt in
            TranscriptionAlternative(
                text: alt.transcript,
                confidence: alt.confidence
            )
        }

        // Calculate audio length (estimate based on data size and format)
        let audioLength = estimateAudioLength(dataSize: audioData.count, format: input.format, sampleRate: sttConfiguration.sampleRate)

        let metadata = TranscriptionMetadata(
            modelId: service.currentModel ?? "unknown",
            processingTime: processingTime,
            audioLength: audioLength
        )

        return STTOutput(
            text: result.transcript,
            confidence: result.confidence ?? 0.9,
            wordTimestamps: wordTimestamps,
            detectedLanguage: result.language,
            alternatives: alternatives,
            metadata: metadata
        )
    }

    /// Stream transcription
    public func streamTranscribe<S: AsyncSequence>(
        _ audioStream: S,
        language: String? = nil
    ) -> AsyncThrowingStream<String, Error> where S.Element == Data {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try ensureReady()

                    guard let service = sttService else {
                        continuation.finish(throwing: SDKError.componentNotReady("STT service not available"))
                        return
                    }

                    let options = STTOptions(
                        language: language ?? sttConfiguration.language,
                        detectLanguage: language == nil,
                        enablePunctuation: sttConfiguration.enablePunctuation,
                        enableDiarization: sttConfiguration.enableDiarization,
                        enableTimestamps: false,
                        vocabularyFilter: sttConfiguration.vocabularyList,
                        audioFormat: .pcm
                    )

                    let result = try await service.streamTranscribe(
                        audioStream: audioStream,
                        options: options
                    ) { partial in
                        continuation.yield(partial)
                    }

                    // Yield final result
                    continuation.yield(result.transcript)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get service for compatibility
    public func getService() -> (any STTService)? {
        return sttService
    }

    // MARK: - Private Helpers

    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.floatChannelData else { return Data() }

        let channelDataValue = channelData.pointee
        let channelDataCount = Int(buffer.frameLength)

        let samples = Array(UnsafeBufferPointer<Float>(
            start: channelDataValue,
            count: channelDataCount
        ))

        return samples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }

    private func estimateAudioLength(dataSize: Int, format: AudioFormat, sampleRate: Int) -> TimeInterval {
        // Rough estimation based on format and sample rate
        let bytesPerSample: Int
        switch format {
        case .pcm, .wav:
            bytesPerSample = 2 // 16-bit PCM
        case .mp3:
            bytesPerSample = 1 // Compressed
        default:
            bytesPerSample = 2
        }

        let samples = dataSize / bytesPerSample
        return TimeInterval(samples) / TimeInterval(sampleRate)
    }
}

// MARK: - Compatibility Typealias
