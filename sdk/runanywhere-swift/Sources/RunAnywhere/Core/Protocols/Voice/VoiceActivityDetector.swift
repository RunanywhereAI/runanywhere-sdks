import Foundation

/// Protocol for voice activity detection in audio streams
public protocol VoiceActivityDetector: AnyObject {
    /// Detect voice activity in a single audio buffer
    /// - Parameter audio: Audio data to analyze
    /// - Returns: VAD result with speech segments and metrics
    func detectActivity(in audio: Data) -> VADResult

    /// Detect voice activity in a streaming audio source
    /// - Parameter audioStream: Async stream of audio chunks
    /// - Returns: Async stream of VAD segments
    func detectActivityStream(
        audioStream: AsyncStream<AudioChunk>
    ) -> AsyncStream<VADSegment>

    /// Sensitivity level for voice detection
    var sensitivity: VADSensitivity { get set }

    /// Energy threshold for voice detection
    var energyThreshold: Float { get set }

    /// Minimum speech duration in seconds to consider valid
    var minSpeechDuration: TimeInterval { get set }

    /// Maximum silence duration in seconds before ending speech
    var maxSilenceDuration: TimeInterval { get set }
}

/// Result of voice activity detection
public struct VADResult {
    /// Whether speech was detected in the audio
    public let hasSpeech: Bool

    /// Detected speech segments with timestamps
    public let speechSegments: [SpeechSegment]

    /// Ratio of silence to total audio duration
    public let silenceRatio: Float

    /// Average energy level in the audio
    public let energyLevel: Float

    /// Zero crossing rate (useful for detecting speech)
    public let zeroCrossingRate: Float

    public init(
        hasSpeech: Bool,
        speechSegments: [SpeechSegment],
        silenceRatio: Float,
        energyLevel: Float,
        zeroCrossingRate: Float
    ) {
        self.hasSpeech = hasSpeech
        self.speechSegments = speechSegments
        self.silenceRatio = silenceRatio
        self.energyLevel = energyLevel
        self.zeroCrossingRate = zeroCrossingRate
    }
}

/// A segment of detected speech
public struct SpeechSegment {
    /// Start time of the speech segment in seconds
    public let startTime: TimeInterval

    /// End time of the speech segment in seconds
    public let endTime: TimeInterval

    /// Average energy level in this segment
    public let averageEnergy: Float

    /// Confidence score for this segment (0.0 to 1.0)
    public let confidence: Float

    public init(
        startTime: TimeInterval,
        endTime: TimeInterval,
        averageEnergy: Float,
        confidence: Float
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.averageEnergy = averageEnergy
        self.confidence = confidence
    }

    /// Duration of the speech segment
    public var duration: TimeInterval {
        endTime - startTime
    }
}

/// VAD segment for streaming detection
public struct VADSegment {
    /// Whether this segment contains speech
    public let isSpeech: Bool

    /// Timestamp of this segment
    public let timestamp: TimeInterval

    /// Energy level at this point
    public let energy: Float

    /// Whether this marks the start of a speech segment
    public let isStartOfSpeech: Bool

    /// Whether this marks the end of a speech segment
    public let isEndOfSpeech: Bool

    public init(
        isSpeech: Bool,
        timestamp: TimeInterval,
        energy: Float,
        isStartOfSpeech: Bool = false,
        isEndOfSpeech: Bool = false
    ) {
        self.isSpeech = isSpeech
        self.timestamp = timestamp
        self.energy = energy
        self.isStartOfSpeech = isStartOfSpeech
        self.isEndOfSpeech = isEndOfSpeech
    }
}

/// Sensitivity levels for voice activity detection
public enum VADSensitivity {
    /// Low sensitivity - Energy threshold: 0.01
    case low

    /// Medium sensitivity - Energy threshold: 0.05
    case medium

    /// High sensitivity - Energy threshold: 0.1
    case high

    /// Custom sensitivity with specific threshold
    case custom(Float)

    /// Get the energy threshold value
    public var threshold: Float {
        switch self {
        case .low:
            return 0.01
        case .medium:
            return 0.05
        case .high:
            return 0.1
        case .custom(let value):
            return value
        }
    }
}
