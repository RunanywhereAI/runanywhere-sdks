import Foundation

/// Represents a voice interaction session
public class VoiceSession {
    /// Unique identifier for this session
    public let id: String

    /// When the session started
    public let startTime: Date

    /// Current state of the session
    public private(set) var state: VoiceSessionState

    /// All transcription results in this session
    public private(set) var transcripts: [VoiceTranscriptionResult] = []

    /// Configuration for this session
    public let configuration: VoiceSessionConfig

    /// End time of the session (nil if still active)
    public private(set) var endTime: Date?

    /// Error that occurred during the session (if any)
    public private(set) var error: Error?

    /// Metadata associated with this session
    public var metadata: [String: Any] = [:]

    /// Lock for thread-safe access
    private let lock = NSLock()

    public init(
        id: String = UUID().uuidString,
        configuration: VoiceSessionConfig = VoiceSessionConfig()
    ) {
        self.id = id
        self.startTime = Date()
        self.state = .idle
        self.configuration = configuration
    }

    /// Duration of the session
    public var duration: TimeInterval {
        if let endTime = endTime {
            return endTime.timeIntervalSince(startTime)
        } else {
            return Date().timeIntervalSince(startTime)
        }
    }

    /// Total transcribed text from all results
    public var totalTranscribedText: String {
        lock.lock()
        defer { lock.unlock() }
        return transcripts.map { $0.text }.joined(separator: " ")
    }

    /// Update the session state
    public func updateState(_ newState: VoiceSessionState) {
        lock.lock()
        defer { lock.unlock() }

        // Validate state transitions
        guard isValidTransition(from: state, to: newState) else {
            return
        }

        state = newState

        if newState == .ended {
            endTime = Date()
        }
    }

    /// Add a transcription result to the session
    public func addTranscript(_ result: VoiceTranscriptionResult) {
        lock.lock()
        defer { lock.unlock() }
        transcripts.append(result)
    }

    /// End the session with an optional error
    public func end(with error: Error? = nil) {
        lock.lock()
        defer { lock.unlock() }

        self.error = error
        state = .ended
        endTime = Date()
    }

    /// Check if a state transition is valid
    private func isValidTransition(from: VoiceSessionState, to: VoiceSessionState) -> Bool {
        switch (from, to) {
        case (.idle, .listening),
             (.idle, .ended),
             (.listening, .processing),
             (.listening, .speaking),
             (.listening, .idle),
             (.listening, .ended),
             (.processing, .speaking),
             (.processing, .listening),
             (.processing, .idle),
             (.processing, .ended),
             (.speaking, .listening),
             (.speaking, .idle),
             (.speaking, .ended):
            return true
        case (.ended, _):
            return false // Cannot transition from ended
        default:
            return from == to // Allow same state
        }
    }
}

/// States of a voice session
public enum VoiceSessionState: String, CaseIterable {
    /// Session is idle, not actively listening
    case idle

    /// Actively listening for speech
    case listening

    /// Processing captured audio
    case processing

    /// Speaking response back to user
    case speaking

    /// Session has ended
    case ended
}

/// Configuration for a voice session
public struct VoiceSessionConfig {
    /// Speech recognition model to use
    public let recognitionModel: String

    /// Text-to-speech model to use (nil to disable TTS)
    public let ttsModel: String?

    /// Whether to enable voice activity detection
    public let enableVAD: Bool

    /// Whether to enable streaming transcription
    public let enableStreaming: Bool

    /// Maximum duration for the session
    public let maxSessionDuration: TimeInterval

    /// Timeout for silence before ending speech segment
    public let silenceTimeout: TimeInterval

    /// Language for recognition
    public let language: String

    /// Whether to use the LLM for processing
    public let useLLM: Bool

    /// LLM model to use if enabled
    public let llmModel: String?

    public init(
        recognitionModel: String = "whisper-base",
        ttsModel: String? = "system",
        enableVAD: Bool = true,
        enableStreaming: Bool = false,
        maxSessionDuration: TimeInterval = 300, // 5 minutes
        silenceTimeout: TimeInterval = 2.0,
        language: String = "en",
        useLLM: Bool = true,
        llmModel: String? = nil
    ) {
        self.recognitionModel = recognitionModel
        self.ttsModel = ttsModel
        self.enableVAD = enableVAD
        self.enableStreaming = enableStreaming
        self.maxSessionDuration = maxSessionDuration
        self.silenceTimeout = silenceTimeout
        self.language = language
        self.useLLM = useLLM
        self.llmModel = llmModel
    }
}
