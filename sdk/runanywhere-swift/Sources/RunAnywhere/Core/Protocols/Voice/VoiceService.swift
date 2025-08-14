import Foundation

/// Protocol for voice transcription services
public protocol VoiceService: AnyObject {
    /// Initialize the voice service with an optional model path
    func initialize(modelPath: String?) async throws

    /// Transcribe audio data to text
    func transcribe(
        audio: Data,
        options: TranscriptionOptions
    ) async throws -> TranscriptionResult

    /// Check if service is ready
    var isReady: Bool { get }

    /// Get current model identifier
    var currentModel: String? { get }

    /// Cleanup resources
    func cleanup() async
}
