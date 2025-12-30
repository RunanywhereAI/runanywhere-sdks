//
//  VADEvent.swift
//  RunAnywhere SDK
//
//  All VAD-related events in one place.
//  Each event declares its destination (public, analytics, or both).
//
//  Note: VADEvent conforms to TelemetryEventProperties for strongly typed analytics.
//  This avoids string conversion/parsing and enables compile-time type checking.
//

import Foundation

// MARK: - VAD Event

/// All VAD (Voice Activity Detection) related events.
///
/// Usage:
/// ```swift
/// EventPublisher.shared.track(VADEvent.initialized(...))
/// ```
///
/// VADEvent provides strongly typed properties via `telemetryProperties`.
/// This enables:
/// - Type safety at compile time
/// - No string parsing for analytics
/// - Validation guardrails (e.g., durationMs >= 0)
public enum VADEvent: SDKEvent, TelemetryEventProperties {

    // MARK: - Service Lifecycle

    /// VAD initialized (no model load for simple VAD, uses built-in algorithms)
    case initialized(framework: InferenceFramework = .builtIn)
    case initializationFailed(error: SDKError, framework: InferenceFramework = .builtIn)
    case cleanedUp

    // MARK: - Model Lifecycle (for model-based VAD)

    /// Model loading started (for model-based VAD like Silero VAD)
    case modelLoadStarted(modelId: String, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    /// Model loading completed
    case modelLoadCompleted(modelId: String, durationMs: Double, modelSizeBytes: Int64 = 0, framework: InferenceFramework = .unknown)
    /// Model loading failed
    case modelLoadFailed(modelId: String, error: SDKError, framework: InferenceFramework = .unknown)
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
        // Use derived properties from telemetryProperties for consistency
        // This eliminates duplicate property conversion logic
        switch self {
        case .initialized, .initializationFailed, .cleanedUp,
             .modelLoadStarted, .modelLoadCompleted, .modelLoadFailed, .modelUnloaded,
             .started, .stopped, .speechStarted, .speechEnded, .paused, .resumed:
            return telemetryProperties.toDictionary()
        }
    }

    // MARK: - TelemetryEventProperties Conformance

    /// Strongly typed telemetry properties - no string conversion needed.
    /// These values are used directly by TelemetryEventPayload.
    public var telemetryProperties: TelemetryProperties {
        switch self {
        case .initialized(let framework):
            return TelemetryProperties(
                framework: framework.rawValue,
                success: true
            )

        case .initializationFailed(let error, let framework):
            return TelemetryProperties(
                framework: framework.rawValue,
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue
            )

        case .cleanedUp:
            return TelemetryProperties()

        case .modelLoadStarted(let modelId, let modelSizeBytes, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadCompleted(let modelId, let durationMs, let modelSizeBytes, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                processingTimeMs: durationMs,
                success: true,
                modelSizeBytes: modelSizeBytes > 0 ? modelSizeBytes : nil
            )

        case .modelLoadFailed(let modelId, let error, let framework):
            return TelemetryProperties(
                modelId: modelId,
                framework: framework.rawValue,
                success: false,
                errorMessage: error.message,
                errorCode: error.code.rawValue
            )

        case .modelUnloaded(let modelId):
            return TelemetryProperties(modelId: modelId)

        case .started:
            return TelemetryProperties()

        case .stopped:
            return TelemetryProperties()

        case .speechStarted:
            return TelemetryProperties()

        case .speechEnded(let durationMs):
            return TelemetryProperties(speechDurationMs: durationMs)

        case .paused:
            return TelemetryProperties()

        case .resumed:
            return TelemetryProperties()
        }
    }
}

// MARK: - VAD Metrics

public struct VADMetrics: Sendable {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let totalSpeechSegments: Int
    public let totalSpeechDurationMs: Double
    public let averageSpeechDurationMs: Double
    public let framework: InferenceFramework

    public init(
        totalEvents: Int = 0,
        startTime: Date = Date(),
        lastEventTime: Date? = nil,
        totalSpeechSegments: Int = 0,
        totalSpeechDurationMs: Double = 0,
        averageSpeechDurationMs: Double = -1,  // -1 indicates N/A
        framework: InferenceFramework = .builtIn
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
