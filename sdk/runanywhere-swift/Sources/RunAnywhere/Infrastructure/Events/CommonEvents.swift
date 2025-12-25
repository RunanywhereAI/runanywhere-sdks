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
    case initFailed(error: String)
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
            return ["error": error]
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
    case downloadFailed(modelId: String, error: String)
    case downloadCancelled(modelId: String)

    // Extraction events (for archive-based models)
    case extractionStarted(modelId: String, archiveType: String)
    case extractionProgress(modelId: String, progress: Double)
    case extractionCompleted(modelId: String, durationMs: Double)
    case extractionFailed(modelId: String, error: String)

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
            return ["model_id": modelId, "error": error]

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
            return ["model_id": modelId, "error": error]

        case .deleted(let modelId):
            return ["model_id": modelId]
        }
    }
}

// MARK: - Storage Event

/// Storage-related events.
public enum StorageEvent: SDKEvent {
    case cacheCleared(freedBytes: Int64)
    case cacheClearFailed(error: String)
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
            return ["error": error]
        case .tempFilesCleaned(let freedBytes):
            return ["freed_bytes": String(freedBytes)]
        }
    }
}

// MARK: - Device Event

/// Device-related events.
public enum DeviceEvent: SDKEvent {
    case registered(deviceId: String)
    case registrationFailed(error: String)

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
            return ["error": error]
        }
    }
}

// MARK: - Network Event

/// Network-related events.
public enum NetworkEvent: SDKEvent {
    case connectivityChanged(isOnline: Bool)
    case requestFailed(url: String, statusCode: Int?, error: String)

    public var type: String {
        switch self {
        case .connectivityChanged: return "network_connectivity_changed"
        case .requestFailed: return "network_request_failed"
        }
    }

    public var category: EventCategory { .network }

    public var destination: EventDestination {
        // Network events are analytics only by default
        .analyticsOnly
    }

    public var properties: [String: String] {
        switch self {
        case .connectivityChanged(let isOnline):
            return ["is_online": String(isOnline)]
        case .requestFailed(let url, let statusCode, let error):
            var props = ["url": url, "error": error]
            if let code = statusCode {
                props["status_code"] = String(code)
            }
            return props
        }
    }
}

// MARK: - Error Event

/// General error events.
public enum ErrorEvent: SDKEvent {
    case error(operation: String, message: String, code: Int?)

    public var type: String { "error" }
    public var category: EventCategory { .error }
    public var destination: EventDestination { .analyticsOnly }

    public var properties: [String: String] {
        switch self {
        case .error(let operation, let message, let code):
            var props = ["operation": operation, "message": message]
            if let code = code {
                props["code"] = String(code)
            }
            return props
        }
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
    case pipelineFailed(error: String)
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
            return ["error": error]
        }
    }
}
