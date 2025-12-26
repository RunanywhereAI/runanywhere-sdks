//
//  CommonEvents.swift
//  RunAnywhere SDK
//
//  Common SDK events (initialization, storage, device, network).
//

import Foundation

// MARK: - SDK Lifecycle Event

/// SDK initialization and lifecycle events.
public enum SDKLifecycleEvent: SDKEvent {
    case initStarted
    case initCompleted(durationMs: Double)
    case initFailed(error: SDKError)
    case modelsLoaded(count: Int)

    public var type: String {
        switch self {
        case .initStarted: return "sdk_init_started"
        case .initCompleted: return "sdk_init_completed"
        case .initFailed: return "sdk_init_failed"
        case .modelsLoaded: return "sdk_models_loaded"
        }
    }

    public var category: EventCategory { .sdk }

    public var properties: [String: String] {
        switch self {
        case .initStarted:
            return [:]
        case .initCompleted(let durationMs):
            return ["duration_ms": String(format: "%.1f", durationMs)]
        case .initFailed(let error):
            return error.telemetryProperties
        case .modelsLoaded(let count):
            return ["count": String(count)]
        }
    }
}

// MARK: - Model Event

/// Common model lifecycle events (download, delete).
/// For capability-specific load/unload, use LLMEvent, STTEvent, TTSEvent.
public enum ModelEvent: SDKEvent {
    // Download events
    case downloadStarted(modelId: String)
    case downloadProgress(modelId: String, progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
    case downloadCompleted(modelId: String, durationMs: Double, sizeBytes: Int64)
    case downloadFailed(modelId: String, error: SDKError)
    case downloadCancelled(modelId: String)

    // Extraction events (for archive-based models)
    case extractionStarted(modelId: String, archiveType: String)
    case extractionProgress(modelId: String, progress: Double)
    case extractionCompleted(modelId: String, durationMs: Double)
    case extractionFailed(modelId: String, error: SDKError)

    // Deletion events
    case deleted(modelId: String)

    public var type: String {
        switch self {
        case .downloadStarted: return "model_download_started"
        case .downloadProgress: return "model_download_progress"
        case .downloadCompleted: return "model_download_completed"
        case .downloadFailed: return "model_download_failed"
        case .downloadCancelled: return "model_download_cancelled"
        case .extractionStarted: return "model_extraction_started"
        case .extractionProgress: return "model_extraction_progress"
        case .extractionCompleted: return "model_extraction_completed"
        case .extractionFailed: return "model_extraction_failed"
        case .deleted: return "model_deleted"
        }
    }

    public var category: EventCategory { .model }

    public var destination: EventDestination {
        switch self {
        case .downloadProgress, .extractionProgress:
            // Progress updates are for public EventBus (UI updates) - not sent to analytics/remote
            return .publicOnly
        default:
            return .all
        }
    }

    public var properties: [String: String] {
        switch self {
        case .downloadStarted(let modelId):
            return ["model_id": modelId]

        case .downloadProgress(let modelId, let progress, let bytes, let total):
            return [
                "model_id": modelId,
                "progress": String(format: "%.1f", progress),
                "bytes_downloaded": String(bytes),
                "total_bytes": String(total)
            ]

        case .downloadCompleted(let modelId, let durationMs, let sizeBytes):
            return [
                "model_id": modelId,
                "duration_ms": String(format: "%.1f", durationMs),
                "size_bytes": String(sizeBytes)
            ]

        case .downloadFailed(let modelId, let error):
            return ["model_id": modelId].merging(error.telemetryProperties) { _, new in new }

        case .downloadCancelled(let modelId):
            return ["model_id": modelId]

        case .extractionStarted(let modelId, let archiveType):
            return ["model_id": modelId, "archive_type": archiveType]

        case .extractionProgress(let modelId, let progress):
            return [
                "model_id": modelId,
                "progress": String(format: "%.1f", progress)
            ]

        case .extractionCompleted(let modelId, let durationMs):
            return [
                "model_id": modelId,
                "duration_ms": String(format: "%.1f", durationMs)
            ]

        case .extractionFailed(let modelId, let error):
            return ["model_id": modelId].merging(error.telemetryProperties) { _, new in new }

        case .deleted(let modelId):
            return ["model_id": modelId]
        }
    }
}

// MARK: - Storage Event

/// Storage-related events.
public enum StorageEvent: SDKEvent {
    case cacheCleared(freedBytes: Int64)
    case cacheClearFailed(error: SDKError)
    case tempFilesCleaned(freedBytes: Int64)

    public var type: String {
        switch self {
        case .cacheCleared: return "storage_cache_cleared"
        case .cacheClearFailed: return "storage_cache_clear_failed"
        case .tempFilesCleaned: return "storage_temp_cleaned"
        }
    }

    public var category: EventCategory { .storage }

    public var properties: [String: String] {
        switch self {
        case .cacheCleared(let freedBytes):
            return ["freed_bytes": String(freedBytes)]
        case .cacheClearFailed(let error):
            return error.telemetryProperties
        case .tempFilesCleaned(let freedBytes):
            return ["freed_bytes": String(freedBytes)]
        }
    }
}

// MARK: - Device Event

/// Device-related events.
public enum DeviceEvent: SDKEvent {
    case registered(deviceId: String)
    case registrationFailed(error: SDKError)

    public var type: String {
        switch self {
        case .registered: return "device_registered"
        case .registrationFailed: return "device_registration_failed"
        }
    }

    public var category: EventCategory { .device }

    public var properties: [String: String] {
        switch self {
        case .registered(let deviceId):
            return ["device_id": deviceId]
        case .registrationFailed(let error):
            return error.telemetryProperties
        }
    }
}

// MARK: - Network Event

/// Network-related events.
public enum NetworkEvent: SDKEvent {
    case connectivityChanged(isOnline: Bool)

    public var type: String {
        switch self {
        case .connectivityChanged: return "network_connectivity_changed"
        }
    }

    public var category: EventCategory { .network }

    public var destination: EventDestination {
        .analyticsOnly
    }

    public var properties: [String: String] {
        switch self {
        case .connectivityChanged(let isOnline):
            return ["is_online": String(isOnline)]
        }
    }
}

// MARK: - SDK Error Event

/// SDK error events - exposed to consumers for error handling and logging.
/// These events carry full error context including stack traces for debugging.
///
/// Consumers can subscribe to these events via EventBus:
/// ```swift
/// EventBus.shared.events(for: .error)
///     .compactMap { $0 as? SDKErrorEvent }
///     .sink { errorEvent in
///         // Log to Sentry, Crashlytics, etc.
///         print("Error: \(errorEvent.error.code) - \(errorEvent.error.message)")
///         print("Stack: \(errorEvent.error.stackTrace)")
///     }
/// ```
public struct SDKErrorEvent: SDKEvent, TypedEventProperties {

    // MARK: - Properties

    /// The underlying SDK error with full context (code, message, category, stack trace)
    public let error: SDKError

    /// The operation that was being performed when the error occurred
    public let operation: String

    /// Additional context about the error (URL, status code, response body, etc.)
    public let context: [String: String]

    // MARK: - SDKEvent Protocol

    public let id: String
    public let timestamp: Date
    public var type: String { "sdk_error" }
    public var category: EventCategory { .error }
    public var sessionId: String? { nil }

    /// Error events go to both consumers (EventBus) and analytics
    /// Consumers can listen to these for error handling/logging
    public var destination: EventDestination { .all }

    public var properties: [String: String] {
        var props = error.telemetryProperties
        props["operation"] = operation

        // Merge context
        for (key, value) in context {
            props[key] = value
        }

        return props
    }

    // MARK: - TypedEventProperties

    public var typedProperties: EventProperties {
        EventProperties(
            errorMessage: error.message,
            errorCode: error.code.rawValue
        )
    }

    // MARK: - Initialization

    public init(
        error: SDKError,
        operation: String,
        context: [String: String] = [:]
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.error = error
        self.operation = operation
        self.context = context
    }

    // MARK: - Factory Methods

    /// Create an error event for a network failure (used by APIClient)
    public static func networkError(
        error: SDKError,
        url: String? = nil,
        statusCode: Int? = nil,
        responseBody: String? = nil
    ) -> SDKErrorEvent {
        var context: [String: String] = [:]
        if let url = url {
            context["url"] = url
        }
        if let statusCode = statusCode {
            context["status_code"] = String(statusCode)
        }
        if let body = responseBody {
            // Truncate long response bodies for logging
            context["response_body"] = String(body.prefix(500))
        }
        return SDKErrorEvent(error: error, operation: "network_request", context: context)
    }

    /// Create an error event for LLM operations (used by analytics services)
    public static func llmError(
        error: SDKError,
        modelId: String? = nil,
        generationId: String? = nil,
        operation: String
    ) -> SDKErrorEvent {
        var context: [String: String] = ["capability": "llm"]
        if let modelId = modelId {
            context["model_id"] = modelId
        }
        if let generationId = generationId {
            context["generation_id"] = generationId
        }
        return SDKErrorEvent(error: error, operation: operation, context: context)
    }

    /// Create an error event for STT operations (used by analytics services)
    public static func sttError(
        error: SDKError,
        modelId: String? = nil,
        transcriptionId: String? = nil,
        operation: String
    ) -> SDKErrorEvent {
        var context: [String: String] = ["capability": "stt"]
        if let modelId = modelId {
            context["model_id"] = modelId
        }
        if let transcriptionId = transcriptionId {
            context["transcription_id"] = transcriptionId
        }
        return SDKErrorEvent(error: error, operation: operation, context: context)
    }

    /// Create an error event for TTS operations (used by analytics services)
    public static func ttsError(
        error: SDKError,
        modelId: String? = nil,
        synthesisId: String? = nil,
        operation: String
    ) -> SDKErrorEvent {
        var context: [String: String] = ["capability": "tts"]
        if let modelId = modelId {
            context["model_id"] = modelId
        }
        if let synthesisId = synthesisId {
            context["synthesis_id"] = synthesisId
        }
        return SDKErrorEvent(error: error, operation: operation, context: context)
    }

    /// Create from any Error, converting to SDKError if needed
    public static func from(
        _ error: Error,
        operation: String,
        context: [String: String] = [:]
    ) -> SDKErrorEvent {
        let sdkError = SDKError.from(error)
        return SDKErrorEvent(error: sdkError, operation: operation, context: context)
    }
}

// MARK: - Framework Event

/// Framework query events (analytics only).
public enum FrameworkEvent: SDKEvent {
    case modelsRequested(framework: String)
    case modelsRetrieved(framework: String, count: Int)

    public var type: String {
        switch self {
        case .modelsRequested: return "framework_models_requested"
        case .modelsRetrieved: return "framework_models_retrieved"
        }
    }

    public var category: EventCategory { .sdk }
    public var destination: EventDestination { .analyticsOnly }

    public var properties: [String: String] {
        switch self {
        case .modelsRequested(let framework):
            return ["framework": framework]
        case .modelsRetrieved(let framework, let count):
            return ["framework": framework, "count": String(count)]
        }
    }
}

// MARK: - Voice Pipeline Event

/// Voice pipeline events (VAD, full pipeline).
public enum VoicePipelineEvent: SDKEvent {
    case pipelineStarted
    case pipelineCompleted(durationMs: Double)
    case pipelineFailed(error: SDKError)
    case vadStarted
    case speechDetected
    case speechEnded
    case vadStopped

    public var type: String {
        switch self {
        case .pipelineStarted: return "voice_pipeline_started"
        case .pipelineCompleted: return "voice_pipeline_completed"
        case .pipelineFailed: return "voice_pipeline_failed"
        case .vadStarted: return "vad_started"
        case .speechDetected: return "vad_speech_detected"
        case .speechEnded: return "vad_speech_ended"
        case .vadStopped: return "vad_stopped"
        }
    }

    public var category: EventCategory { .voice }

    public var properties: [String: String] {
        switch self {
        case .pipelineStarted, .vadStarted, .speechDetected, .speechEnded, .vadStopped:
            return [:]
        case .pipelineCompleted(let durationMs):
            return ["duration_ms": String(format: "%.1f", durationMs)]
        case .pipelineFailed(let error):
            return error.telemetryProperties
        }
    }
}
