import Foundation

/// Protocol for voice transcription services
public protocol VoiceService: AnyObject {
    /// Initialize the voice service with an optional model path
    func initialize(modelPath: String?) async throws

    /// Transcribe audio data to text
    func transcribe(
        audio: Data,
        options: VoiceTranscriptionOptions
    ) async throws -> VoiceTranscriptionResult

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
        options: VoiceTranscriptionOptions
    ) -> AsyncThrowingStream<VoiceTranscriptionSegment, Error>

    /// Check if streaming is supported
    var supportsStreaming: Bool { get }

    /// Get supported languages
    var supportedLanguages: [String] { get }
}

// MARK: - Default implementations for optional methods
public extension VoiceService {
    /// Default implementation returns unsupported stream
    func transcribeStream(
        audioStream: AsyncStream<VoiceAudioChunk>,
        options: VoiceTranscriptionOptions
    ) -> AsyncThrowingStream<VoiceTranscriptionSegment, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: VoiceError.streamingNotSupported)
        }
    }

    /// Default implementation returns false
    var supportsStreaming: Bool { false }

    /// Default implementation returns common languages
    var supportedLanguages: [String] {
        ["en", "es", "fr", "de", "it", "pt", "ru", "zh", "ja", "ko"]
    }
}

/// Errors for voice services
public enum VoiceError: LocalizedError {
    case serviceNotInitialized
    case transcriptionFailed(Error)
    case streamingNotSupported
    case languageNotSupported(String)
    case modelNotFound(String)
    case audioFormatNotSupported
    case insufficientAudioData
    case noVoiceServiceAvailable

    public var errorDescription: String? {
        switch self {
        case .serviceNotInitialized:
            return "Voice service is not initialized"
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
            return "No voice service available for transcription"
        }
    }
}
