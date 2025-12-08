import Foundation

/// Configuration for a voice session
public struct VoiceSessionConfig {
    public let enableTranscription: Bool
    public let enableLLM: Bool
    public let enableTTS: Bool
    public let language: String

    public init(
        enableTranscription: Bool = true,
        enableLLM: Bool = false,
        enableTTS: Bool = false,
        language: String = "en"
    ) {
        self.enableTranscription = enableTranscription
        self.enableLLM = enableLLM
        self.enableTTS = enableTTS
        self.language = language
    }
}

/// Voice session state tracking
public struct VoiceSession {
    public let id: String
    public let configuration: VoiceSessionConfig
    public var state: VoiceSessionState
    public var transcripts: [STTResult]
    public var startTime: Date?
    public var endTime: Date?

    public var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }

    public init(
        id: String,
        configuration: VoiceSessionConfig,
        state: VoiceSessionState = .idle
    ) {
        self.id = id
        self.configuration = configuration
        self.state = state
        self.transcripts = []
        self.startTime = nil
        self.endTime = nil
    }
}

/// Voice session state
public enum VoiceSessionState: String {
    case idle
    case listening
    case processing
    case speaking
    case ended
    case error
}
