import Foundation

// MARK: - STT Initialization Parameters

/// Initialization parameters specific to STT component
public struct STTInitParameters: ComponentInitParameters {
    public let componentType = SDKComponent.stt
    public let modelId: String?

    // STT-specific parameters
    public let language: String
    public let sampleRate: Int
    public let enablePunctuation: Bool
    public let enableDiarization: Bool
    public let vocabularyList: [String]
    public let maxAlternatives: Int

    public init(
        modelId: String? = nil,
        language: String = "en-US",
        sampleRate: Int = 16000,
        enablePunctuation: Bool = true,
        enableDiarization: Bool = false,
        vocabularyList: [String] = [],
        maxAlternatives: Int = 1
    ) {
        self.modelId = modelId
        self.language = language
        self.sampleRate = sampleRate
        self.enablePunctuation = enablePunctuation
        self.enableDiarization = enableDiarization
        self.vocabularyList = vocabularyList
        self.maxAlternatives = maxAlternatives
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

// MARK: - Service Protocol

/// Enum to specify preferred audio format for the service
public enum STTServiceAudioFormat {
    case data       // Service prefers raw Data
    case floatArray // Service prefers Float array samples
}

/// Protocol for voice transcription services
public protocol STTService: AnyObject {
    /// Initialize the STT service with an optional model path
    func initialize(modelPath: String?) async throws

    /// Transcribe audio data to text
    func transcribe(
        audio: Data,
        options: STTOptions
    ) async throws -> STTResult

    /// Transcribe audio samples to text (optional - implement if preferred format is floatArray)
    func transcribe(
        samples: [Float],
        options: STTOptions
    ) async throws -> STTResult

    /// Preferred audio format for this service
    var preferredAudioFormat: STTServiceAudioFormat { get }

    /// Check if service is ready
    var isReady: Bool { get }

    /// Get current model identifier
    var currentModel: String? { get }

    /// Cleanup resources
    func cleanup() async

    /// Transcribe streaming audio
    /// - Parameters:
    ///   - audioStream: Stream of audio chunks
    ///   - options: Transcription options
    /// - Returns: Stream of transcription segments
    func transcribeStream(
        audioStream: AsyncStream<VoiceAudioChunk>,
        options: STTOptions
    ) -> AsyncThrowingStream<STTSegment, Error>

    /// Check if streaming is supported
    var supportsStreaming: Bool { get }

    /// Get supported languages
    var supportedLanguages: [String] { get }
}

// MARK: - Default implementations for optional methods
public extension STTService {
    /// Default implementation for Float array transcription - converts to Data
    func transcribe(
        samples: [Float],
        options: STTOptions
    ) async throws -> STTResult {
        // Default implementation converts Float array to Data
        let data = samples.withUnsafeBytes { bytes in
            Data(bytes)
        }
        return try await transcribe(audio: data, options: options)
    }

    /// Default preferred format is Data for backward compatibility
    var preferredAudioFormat: STTServiceAudioFormat { .data }

    /// Default implementation returns unsupported stream
    func transcribeStream(
        audioStream: AsyncStream<VoiceAudioChunk>,
        options: STTOptions
    ) -> AsyncThrowingStream<STTSegment, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: STTError.streamingNotSupported)
        }
    }

    /// Default implementation returns false
    var supportsStreaming: Bool { false }

    /// Default implementation returns common languages
    var supportedLanguages: [String] {
        ["en", "es", "fr", "de", "it", "pt", "ru", "zh", "ja", "ko"]
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
