//
//  SpeakerDiarizationEvent.swift
//  RunAnywhere SDK
//
//  Speaker diarization events using the unified event system.
//

import Foundation

// MARK: - Speaker Diarization Event

/// Speaker diarization events.
public enum SpeakerDiarizationEvent: SDKEvent {
    case sessionStarted(sessionId: String, framework: InferenceFrameworkType = .unknown)
    case sessionCompleted(sessionId: String, durationMs: Double, speakersDetected: Int, framework: InferenceFrameworkType = .unknown)
    case speakerDetected(speakerId: String, confidence: Float)
    case speakerChanged(fromSpeaker: String?, toSpeaker: String)
    case error(sessionId: String, message: String)

    public var type: String {
        switch self {
        case .sessionStarted: return "speaker_diarization_session_started"
        case .sessionCompleted: return "speaker_diarization_session_completed"
        case .speakerDetected: return "speaker_diarization_speaker_detected"
        case .speakerChanged: return "speaker_diarization_speaker_changed"
        case .error: return "speaker_diarization_error"
        }
    }

    public var category: EventCategory { .voice }

    public var destination: EventDestination {
        switch self {
        case .speakerDetected, .speakerChanged:
            // Internal metrics only
            return .analyticsOnly
        default:
            return .all
        }
    }

    public var properties: [String: String] {
        switch self {
        case .sessionStarted(let sessionId, let framework):
            return [
                "session_id": sessionId,
                "framework": framework.rawValue
            ]

        case .sessionCompleted(let sessionId, let durationMs, let speakersDetected, let framework):
            return [
                "session_id": sessionId,
                "duration_ms": String(format: "%.1f", durationMs),
                "speakers_detected": String(speakersDetected),
                "framework": framework.rawValue
            ]

        case .speakerDetected(let speakerId, let confidence):
            return [
                "speaker_id": speakerId,
                "confidence": String(format: "%.3f", confidence)
            ]

        case .speakerChanged(let fromSpeaker, let toSpeaker):
            var props = ["to_speaker": toSpeaker]
            if let from = fromSpeaker {
                props["from_speaker"] = from
            }
            return props

        case .error(let sessionId, let message):
            return ["session_id": sessionId, "error": message]
        }
    }
}

// MARK: - Speaker Diarization Metrics

public struct SpeakerDiarizationMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSessions: Int
    public let totalSpeakersDetected: Int
    public let averageProcessingTimeMs: Double
    public let framework: InferenceFrameworkType

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalSessions: Int = 0,
        totalSpeakersDetected: Int = 0,
        averageProcessingTimeMs: Double = -1,  // -1 indicates N/A
        framework: InferenceFrameworkType = .unknown
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalSessions = totalSessions
        self.totalSpeakersDetected = totalSpeakersDetected
        self.averageProcessingTimeMs = averageProcessingTimeMs
        self.framework = framework
    }
}
