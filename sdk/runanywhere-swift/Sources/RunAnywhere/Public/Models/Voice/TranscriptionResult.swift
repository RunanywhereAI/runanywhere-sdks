import Foundation

/// Result from speech-to-text transcription
public struct TranscriptionResult {
    /// The transcribed text
    public let text: String

    /// Detected language (if available)
    public let language: String?

    /// Confidence score (0.0 to 1.0)
    public let confidence: Float

    /// Duration of the audio
    public let duration: TimeInterval

    public init(
        text: String,
        language: String? = nil,
        confidence: Float = 0.0,
        duration: TimeInterval = 0.0
    ) {
        self.text = text
        self.language = language
        self.confidence = confidence
        self.duration = duration
    }
}
