import Foundation

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
