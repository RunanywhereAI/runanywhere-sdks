//
//  VADEvent.swift
//  RunAnywhere SDK
//
//  All VAD-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//

import Foundation

// MARK: - VAD Event

/// All VAD (Voice Activity Detection) related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(VADEvent.initialized(...))
/// ```
public enum VADEvent: SDKEvent {

    // MARK: - Service Lifecycle

    /// VAD initialized (no model load for simple VAD, uses built-in algorithms)
    case initialized(framework: InferenceFrameworkType = .builtIn)
    case initializationFailed(error: String, framework: InferenceFrameworkType = .builtIn)
    case cleanedUp

    // MARK: - Detection

    case started
    case stopped
    case speechDetected(durationMs: Double)
    case speechEnded(durationMs: Double)
    case paused
    case resumed

    // MARK: - SDKEvent Conformance

    public var type: String {
        switch self {
        case .initialized: return "vad_initialized"
        case .initializationFailed: return "vad_initialization_failed"
        case .cleanedUp: return "vad_cleaned_up"
        case .started: return "vad_started"
        case .stopped: return "vad_stopped"
        case .speechDetected: return "vad_speech_detected"
        case .speechEnded: return "vad_speech_ended"
        case .paused: return "vad_paused"
        case .resumed: return "vad_resumed"
        }
    }

    public var category: EventCategory { .voice }

    public var destination: EventDestination {
        switch self {
        // Speech detection events are analytics only (too chatty)
        case .speechDetected, .speechEnded:
            return .analyticsOnly
        default:
            return .all
        }
    }

    public var properties: [String: String] {
        switch self {
        case .initialized(let framework):
            return ["framework": framework.rawValue]

        case .initializationFailed(let error, let framework):
            return [
                "error": error,
                "framework": framework.rawValue
            ]

        case .cleanedUp:
            return [:]

        case .started:
            return [:]

        case .stopped:
            return [:]

        case .speechDetected(let durationMs):
            return ["duration_ms": String(format: "%.1f", durationMs)]

        case .speechEnded(let durationMs):
            return ["duration_ms": String(format: "%.1f", durationMs)]

        case .paused:
            return [:]

        case .resumed:
            return [:]
        }
    }
}

// MARK: - VAD Metrics

public struct VADMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSpeechSegments: Int
    public let totalSpeechDurationMs: Double
    public let averageSpeechDurationMs: Double
    public let framework: InferenceFrameworkType

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalSpeechSegments: Int = 0,
        totalSpeechDurationMs: Double = 0,
        averageSpeechDurationMs: Double = -1,  // -1 indicates N/A
        framework: InferenceFrameworkType = .builtIn
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.totalSpeechSegments = totalSpeechSegments
        self.totalSpeechDurationMs = totalSpeechDurationMs
        self.averageSpeechDurationMs = averageSpeechDurationMs
        self.framework = framework
    }
}
