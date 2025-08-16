import Foundation

/// Options for transcription
public struct VoiceTranscriptionOptions {
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

    public init(
        language: Language = .auto,
        task: Task = .transcribe
    ) {
        self.language = language
        self.task = task
    }
}
