import Foundation

/// Protocol for speaker diarization implementations
/// Allows for default SDK implementation, FluidAudio module, or custom implementations
public protocol SpeakerDiarizationProtocol: AnyObject {
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
public extension SpeakerDiarizationProtocol {
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
