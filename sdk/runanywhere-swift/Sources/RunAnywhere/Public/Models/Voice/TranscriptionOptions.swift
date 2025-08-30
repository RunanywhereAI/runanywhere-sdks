import Foundation

/// Options for transcription
public struct STTOptions {
    /// Language for transcription
    public enum Language: String {
        case auto = "auto"
        case english = "en"
        case spanish = "es"
        case french = "fr"
        case german = "de"
        case chinese = "zh"
        case japanese = "ja"
    }

    /// Transcription task type
    public enum Task {
        case transcribe
        case translate
    }

    /// Language to use for transcription
    public var language: Language

    /// Task to perform
    public var task: Task

    /// Enable speaker diarization (detect different speakers)
    public var enableSpeakerDiarization: Bool

    /// Maximum number of speakers to detect (nil for automatic)
    public var maxSpeakers: Int?

    /// Minimum duration for speaker segments (in seconds)
    public var minSpeakerDuration: TimeInterval

    /// Enable continuous mode for real-time streaming
    public var continuousMode: Bool

    public init(
        language: Language = .auto,
        task: Task = .transcribe,
        enableSpeakerDiarization: Bool = false,
        maxSpeakers: Int? = nil,
        minSpeakerDuration: TimeInterval = 1.0,
        continuousMode: Bool = false
    ) {
        self.language = language
        self.task = task
        self.enableSpeakerDiarization = enableSpeakerDiarization
        self.maxSpeakers = maxSpeakers
        self.minSpeakerDuration = minSpeakerDuration
        self.continuousMode = continuousMode
    }
}
