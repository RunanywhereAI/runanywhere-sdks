import Foundation

/// Speaker information in a transcription
public struct SpeakerInfo: Codable, Equatable {
    /// Unique speaker identifier
    public let id: String

    /// Optional speaker name (can be set by user)
    public var name: String?

    /// Speaker embedding/features for comparison
    public let embedding: [Float]?

    public init(id: String, name: String? = nil, embedding: [Float]? = nil) {
        self.id = id
        self.name = name
        self.embedding = embedding
    }
}

/// Result from speech-to-text transcription
public struct STTResult {
    /// The transcribed text
    public let text: String

    /// Detected language (if available)
    public let language: String?

    /// Confidence score (0.0 to 1.0)
    public let confidence: Float

    /// Duration of the audio
    public let duration: TimeInterval

    /// Speaker information (for diarization)
    public let speaker: SpeakerInfo?

    /// Start time of this segment (for continuous transcription)
    public let startTime: TimeInterval?

    /// End time of this segment
    public let endTime: TimeInterval?

    public init(
        text: String,
        language: String? = nil,
        confidence: Float = 0.0,
        duration: TimeInterval = 0.0,
        speaker: SpeakerInfo? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil
    ) {
        self.text = text
        self.language = language
        self.confidence = confidence
        self.duration = duration
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
    }
}
