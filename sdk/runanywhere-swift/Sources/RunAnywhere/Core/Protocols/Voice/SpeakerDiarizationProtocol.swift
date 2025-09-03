import Foundation

/// Information about a detected speaker
public struct SpeakerInfo {
    public let id: String
    public var name: String?
    public let confidence: Float
    public let firstDetectedAt: TimeInterval
    public let lastDetectedAt: TimeInterval
    public let totalSpeakingTime: TimeInterval
    public let embedding: [Float]?

    public init(
        id: String,
        name: String? = nil,
        confidence: Float = 1.0,
        firstDetectedAt: TimeInterval = 0,
        lastDetectedAt: TimeInterval = 0,
        totalSpeakingTime: TimeInterval = 0,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.name = name
        self.confidence = confidence
        self.firstDetectedAt = firstDetectedAt
        self.lastDetectedAt = lastDetectedAt
        self.totalSpeakingTime = totalSpeakingTime
        self.embedding = embedding
    }
}

/// Protocol for speaker diarization implementations
/// Allows for default SDK implementation, FluidAudio module, or custom implementations
public protocol SpeakerDiarizationService: AnyObject {
    // Core methods that all implementations must provide
    func detectSpeaker(from audioBuffer: [Float], sampleRate: Int) -> SpeakerInfo
    func updateSpeakerName(speakerId: String, name: String)
    func getAllSpeakers() -> [SpeakerInfo]
    func getCurrentSpeaker() -> SpeakerInfo?
    func reset()

    // Optional advanced features (FluidAudio can implement these)
    func performDetailedDiarization(audioBuffer: [Float]) async throws -> SpeakerDiarizationResult?
    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float
}

// Default implementation for optional methods
public extension SpeakerDiarizationService {
    func performDetailedDiarization(audioBuffer: [Float]) async throws -> SpeakerDiarizationResult? {
        return nil // Default returns nil, advanced implementations can override
    }

    func compareSpeakers(audio1: [Float], audio2: [Float]) async throws -> Float {
        return 0.0 // Default returns 0, advanced implementations can override
    }
}

/// Result from detailed diarization (used by advanced implementations like FluidAudio)
public struct SpeakerDiarizationResult {
    public let segments: [SpeakerSegment]
    public let speakers: [SpeakerInfo]

    public init(segments: [SpeakerSegment], speakers: [SpeakerInfo]) {
        self.segments = segments
        self.speakers = speakers
    }
}

/// A segment of audio with speaker information
public struct SpeakerSegment {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let speakerId: String
    public let confidence: Float

    public init(startTime: TimeInterval, endTime: TimeInterval, speakerId: String, confidence: Float) {
        self.startTime = startTime
        self.endTime = endTime
        self.speakerId = speakerId
        self.confidence = confidence
    }
}
