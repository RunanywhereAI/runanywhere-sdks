import Foundation

/// A segment of transcribed text from streaming audio
public struct STTSegment {
    /// The transcribed text
    public let text: String

    /// Start time of this segment in the audio stream
    public let startTime: TimeInterval

    /// End time of this segment in the audio stream
    public let endTime: TimeInterval

    /// Whether this is a final transcription or may be updated
    public let isFinal: Bool

    /// Confidence score for this transcription (0.0 to 1.0)
    public let confidence: Float

    /// Language detected for this segment
    public let language: String?

    /// Alternative transcriptions with their confidence scores
    public let alternatives: [(text: String, confidence: Float)]

    /// Word-level timestamps if available
    public let wordTimestamps: [WordTimestamp]?

    /// Speaker information for this segment
    public let speaker: SpeakerInfo?

    public init(
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        isFinal: Bool = false,
        confidence: Float = 1.0,
        language: String? = nil,
        alternatives: [(text: String, confidence: Float)] = [],
        wordTimestamps: [WordTimestamp]? = nil,
        speaker: SpeakerInfo? = nil
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.isFinal = isFinal
        self.confidence = confidence
        self.language = language
        self.alternatives = alternatives
        self.wordTimestamps = wordTimestamps
        self.speaker = speaker
    }

    /// Duration of this segment
    public var duration: TimeInterval {
        endTime - startTime
    }
}

/// Word-level timestamp information
public struct WordTimestamp {
    /// The word
    public let word: String

    /// Start time of the word
    public let startTime: TimeInterval

    /// End time of the word
    public let endTime: TimeInterval

    /// Confidence score for this word
    public let confidence: Float

    public init(
        word: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Float = 1.0
    ) {
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}
