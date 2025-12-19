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

    // MARK: - Model Lifecycle (for model-based VAD)

    /// Model loading started (for model-based VAD like Silero VAD)
    case modelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType = .unknown)
    /// Model loading completed
    case modelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFrameworkType = .unknown)
    /// Model loading failed
    case modelLoadFailed(modelId: String, error: String, framework: InferenceFrameworkType = .unknown)
    /// Model unloaded
    case modelUnloaded(modelId: String)

    // MARK: - Detection

    case started
    case stopped
    /// Speech started (voice activity detected)
    case speechStarted
    /// Speech ended with duration
    case speechEnded(durationMs: Double)
    case paused
    case resumed

    // MARK: - SDKEvent Conformance

    public var type: String {
        switch self {
        case .initialized: return "vad_initialized"
        case .initializationFailed: return "vad_initialization_failed"
        case .cleanedUp: return "vad_cleaned_up"
        case .modelLoadStarted: return "vad_model_load_started"
        case .modelLoadCompleted: return "vad_model_load_completed"
        case .modelLoadFailed: return "vad_model_load_failed"
        case .modelUnloaded: return "vad_model_unloaded"
        case .started: return "vad_started"
        case .stopped: return "vad_stopped"
        case .speechStarted: return "vad_speech_started"
        case .speechEnded: return "vad_speech_ended"
        case .paused: return "vad_paused"
        case .resumed: return "vad_resumed"
        }
    }

    public var category: EventCategory { .voice }

    public var destination: EventDestination {
        switch self {
        // Speech detection events are analytics only (too chatty)
        case .speechStarted, .speechEnded:
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

        case .modelLoadStarted(let modelId, let modelSizeBytes, let framework):
            var props = [
                "model_id": modelId,
                "framework": framework.rawValue
            ]
            if modelSizeBytes > 0 {
                props["model_size_bytes"] = String(modelSizeBytes)
            }
            return props

        case .modelLoadCompleted(let modelId, let durationMs, let modelSizeBytes, let framework):
            var props = [
                "model_id": modelId,
                "duration_ms": String(format: "%.1f", durationMs),
                "framework": framework.rawValue
            ]
            if modelSizeBytes > 0 {
                props["model_size_bytes"] = String(modelSizeBytes)
            }
            return props

        case .modelLoadFailed(let modelId, let error, let framework):
            return [
                "model_id": modelId,
                "error": error,
                "framework": framework.rawValue
            ]

        case .modelUnloaded(let modelId):
            return ["model_id": modelId]

        case .started:
            return [:]

        case .stopped:
            return [:]

        case .speechStarted:
            return [:]

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
