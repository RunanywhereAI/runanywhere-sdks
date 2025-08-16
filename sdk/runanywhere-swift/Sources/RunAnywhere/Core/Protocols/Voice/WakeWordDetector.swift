import Foundation

/// Protocol for wake word detection in audio streams
public protocol WakeWordDetector: AnyObject {
    /// Initialize the detector with specific wake words
    /// - Parameter wakeWords: Array of wake words to detect
    func initialize(wakeWords: [String]) async throws

    /// Start listening for wake words
    func startListening() async throws

    /// Stop listening for wake words
    func stopListening() async

    /// Process an audio buffer for wake word detection
    /// - Parameter audio: Audio data to analyze
    /// - Returns: Detection result if wake word found
    func processAudio(_ audio: Data) async -> WakeWordDetection?

    /// Process streaming audio for wake word detection
    /// - Parameter audioStream: Stream of audio chunks
    /// - Returns: Stream of wake word detections
    func processStream(
        _ audioStream: AsyncStream<VoiceAudioChunk>
    ) -> AsyncThrowingStream<WakeWordDetection, Error>

    /// Whether the detector is currently listening
    var isListening: Bool { get }

    /// Current wake words being detected
    var wakeWords: [String] { get }

    /// Sensitivity level for detection (0.0 to 1.0)
    var sensitivity: Float { get set }

    /// Callback when wake word is detected
    var onWakeWordDetected: ((WakeWordDetection) -> Void)? { get set }

    /// Callback when listening state changes
    var onListeningStateChanged: ((Bool) -> Void)? { get set }

    /// Add a new wake word to detection
    /// - Parameter word: Wake word to add
    func addWakeWord(_ word: String) async throws

    /// Remove a wake word from detection
    /// - Parameter word: Wake word to remove
    func removeWakeWord(_ word: String) async

    /// Clear all wake words
    func clearWakeWords() async
}

/// Result of wake word detection
public struct WakeWordDetection {
    /// The detected wake word
    public let wakeWord: String

    /// Confidence score of the detection (0.0 to 1.0)
    public let confidence: Float

    /// Timestamp when the wake word was detected
    public let timestamp: TimeInterval

    /// Audio segment containing the wake word
    public let audioSegment: Data?

    /// Start time of the wake word in the audio
    public let startTime: TimeInterval

    /// End time of the wake word in the audio
    public let endTime: TimeInterval

    /// Whether this is a confirmed detection (above threshold)
    public let isConfirmed: Bool

    public init(
        wakeWord: String,
        confidence: Float,
        timestamp: TimeInterval,
        audioSegment: Data? = nil,
        startTime: TimeInterval,
        endTime: TimeInterval,
        isConfirmed: Bool = true
    ) {
        self.wakeWord = wakeWord
        self.confidence = confidence
        self.timestamp = timestamp
        self.audioSegment = audioSegment
        self.startTime = startTime
        self.endTime = endTime
        self.isConfirmed = isConfirmed
    }

    /// Duration of the wake word
    public var duration: TimeInterval {
        endTime - startTime
    }
}

/// Configuration for wake word detection
public struct WakeWordConfig {
    /// Wake words to detect
    public let wakeWords: [String]

    /// Minimum confidence threshold for detection
    public let confidenceThreshold: Float

    /// Whether to continue listening after detection
    public let continuousListening: Bool

    /// Audio preprocessing options
    public let preprocessingEnabled: Bool

    /// Noise suppression level
    public let noiseSuppression: NoiseSuppressionLevel

    /// Model to use for wake word detection
    public let modelPath: String?

    /// Buffer size for audio processing
    public let bufferSize: Int

    /// Sample rate for audio input
    public let sampleRate: Int

    public init(
        wakeWords: [String],
        confidenceThreshold: Float = 0.7,
        continuousListening: Bool = true,
        preprocessingEnabled: Bool = true,
        noiseSuppression: NoiseSuppressionLevel = .medium,
        modelPath: String? = nil,
        bufferSize: Int = 1024,
        sampleRate: Int = 16000
    ) {
        self.wakeWords = wakeWords
        self.confidenceThreshold = confidenceThreshold
        self.continuousListening = continuousListening
        self.preprocessingEnabled = preprocessingEnabled
        self.noiseSuppression = noiseSuppression
        self.modelPath = modelPath
        self.bufferSize = bufferSize
        self.sampleRate = sampleRate
    }
}

/// Noise suppression levels for wake word detection
public enum NoiseSuppressionLevel: String, CaseIterable {
    /// No noise suppression
    case none

    /// Light noise suppression
    case low

    /// Moderate noise suppression
    case medium

    /// Aggressive noise suppression
    case high

    /// Get the suppression factor
    public var factor: Float {
        switch self {
        case .none:
            return 0.0
        case .low:
            return 0.25
        case .medium:
            return 0.5
        case .high:
            return 0.75
        }
    }
}
