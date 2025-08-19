import Foundation

/// Configuration for Speech-to-Text processing
public struct VoiceSTTConfig {
    /// Model identifier for STT
    public let modelId: String

    /// Language for transcription
    public let language: String

    /// Enable streaming transcription
    public let streamingEnabled: Bool

    /// Enable partial results during streaming
    public let partialResults: Bool

    public init(
        modelId: String = "whisper-base",
        language: String = "en",
        streamingEnabled: Bool = true,
        partialResults: Bool = true
    ) {
        self.modelId = modelId
        self.language = language
        self.streamingEnabled = streamingEnabled
        self.partialResults = partialResults
    }
}
