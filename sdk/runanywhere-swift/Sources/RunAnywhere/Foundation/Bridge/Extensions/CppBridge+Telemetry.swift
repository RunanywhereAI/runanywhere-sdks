//
//  CppBridge+Telemetry.swift
//  RunAnywhere SDK
//
//  Telemetry bridge for C++ interop.
//  All events originate from C++ - Swift only provides HTTP transport.
//

import CRACommons
import Foundation

// MARK: - Events Bridge

extension CppBridge {

    /// Analytics events bridge
    /// C++ handles all event logic - Swift just handles HTTP transport
    public enum Events {

        private static var isRegistered = false

        /// Register C++ event callbacks
        /// Only analytics callback is needed - for telemetry HTTP transport
        static func register() {
            guard !isRegistered else { return }

            // Register analytics callback (receives TELEMETRY_ONLY and ALL events)
            // This forwards to C++ telemetry manager which builds JSON and calls HTTP callback
            let result = rac_analytics_events_set_callback(analyticsEventCallback, nil)
            if result != RAC_SUCCESS {
                SDKLogger(category: "CppBridge.Events").warning("Failed to register analytics callback")
            }

            // Note: Public events are handled directly by app developers via C++ callbacks
            // No Swift EventPublisher layer needed

            isRegistered = true
            SDKLogger(category: "CppBridge.Events").debug("Registered C++ event callbacks")
        }

        /// Unregister C++ event callbacks
        static func unregister() {
            guard isRegistered else { return }
            _ = rac_analytics_events_set_callback(nil, nil)
            isRegistered = false
        }
    }
}

/// Analytics callback - handles telemetry (C++ routes TELEMETRY_ONLY and ALL here)
private func analyticsEventCallback(
    type: rac_event_type_t,
    data: UnsafePointer<rac_analytics_event_data_t>?,
    userData _: UnsafeMutableRawPointer?
) {
    guard let data = data else {
        return
    }
    // Forward to telemetry manager (C++ builds JSON, calls HTTP callback)
    CppBridge.Telemetry.trackAnalyticsEvent(type: type, data: data)
}

// MARK: - Telemetry Bridge

extension CppBridge {

    /// Telemetry bridge
    /// C++ handles JSON building, batching; Swift handles HTTP transport only
    public enum Telemetry {

        private static var manager: OpaquePointer?
        private static let lock = NSLock()

        /// Initialize telemetry manager
        static func initialize(environment: SDKEnvironment) {
            lock.lock()
            defer { lock.unlock() }

            // Destroy existing if any
            if let existing = manager {
                rac_telemetry_manager_destroy(existing)
            }

            let deviceId = DeviceIdentity.persistentUUID
            let deviceInfo = DeviceInfo.current

            manager = deviceId.withCString { did in
                SDKConstants.platform.withCString { plat in
                    SDKConstants.version.withCString { ver in
                        rac_telemetry_manager_create(Environment.toC(environment), did, plat, ver)
                    }
                }
            }

            // Set device info
            deviceInfo.deviceModel.withCString { model in
                deviceInfo.osVersion.withCString { os in
                    rac_telemetry_manager_set_device_info(manager, model, os)
                }
            }

            // Register HTTP callback - Swift provides HTTP transport for C++
            let userData = Unmanaged.passUnretained(Telemetry.self as AnyObject).toOpaque()
            rac_telemetry_manager_set_http_callback(manager, telemetryHttpCallback, userData)
        }

        /// Shutdown telemetry manager
        static func shutdown() {
            lock.lock()
            defer { lock.unlock() }

            if let mgr = manager {
                rac_telemetry_manager_flush(mgr)
                rac_telemetry_manager_destroy(mgr)
                manager = nil
            }
        }

        /// Track analytics event from C++
        static func trackAnalyticsEvent(
            type: rac_event_type_t,
            data: UnsafePointer<rac_analytics_event_data_t>
        ) {
            lock.lock()
            let mgr = manager
            lock.unlock()

            guard let mgr = mgr else { return }
            rac_telemetry_manager_track_analytics(mgr, type, data)
        }

        /// Flush pending events
        public static func flush() {
            lock.lock()
            let mgr = manager
            lock.unlock()

            guard let mgr = mgr else { return }
            rac_telemetry_manager_flush(mgr)
        }
    }
}

/// HTTP callback for telemetry - Swift provides HTTP transport for C++ telemetry
private func telemetryHttpCallback(
    userData _: UnsafeMutableRawPointer?,
    endpoint: UnsafePointer<CChar>?,
    jsonBody: UnsafePointer<CChar>?,
    jsonLength _: Int,
    requiresAuth: rac_bool_t
) {
    guard let endpoint = endpoint, let jsonBody = jsonBody else { return }

    let path = String(cString: endpoint)
    let json = String(cString: jsonBody)
    let needsAuth = requiresAuth == RAC_TRUE

    Task {
        await performTelemetryHTTP(path: path, json: json, requiresAuth: needsAuth)
    }
}

private func performTelemetryHTTP(path: String, json: String, requiresAuth: Bool) async {
    let logger = SDKLogger(category: "CppBridge.Telemetry")

    // Check if HTTP is configured before attempting request
    let isConfigured = await CppBridge.HTTP.shared.isConfigured
    guard isConfigured else {
        logger.debug("HTTP not configured, cannot send telemetry to \(path). Events will be queued.")
        return
    }

    do {
        _ = try await CppBridge.HTTP.shared.post(path, json: json, requiresAuth: requiresAuth)
        logger.debug("✅ Telemetry sent to \(path)")
    } catch {
        logger.error("❌ HTTP failed for telemetry to \(path): \(error)")
    }
}

// MARK: - Event Emission Helpers (for Swift code that needs to emit events to C++)

extension CppBridge.Events {

    // MARK: - Download Events

    /// Emit download started event via C++
    public static func emitDownloadStarted(modelId: String, totalBytes: Int64 = 0) {
        modelId.withCString { modelIdPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_MODEL_DOWNLOAD_STARTED
            eventData.data.model_download.model_id = modelIdPtr
            eventData.data.model_download.total_bytes = totalBytes
            eventData.data.model_download.progress = 0
            eventData.data.model_download.bytes_downloaded = 0
            eventData.data.model_download.duration_ms = 0
            eventData.data.model_download.error_code = RAC_SUCCESS
            eventData.data.model_download.error_message = nil
            rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_STARTED, &eventData)
        }
    }

    /// Emit download progress event via C++
    public static func emitDownloadProgress(modelId: String, progress: Double, bytesDownloaded: Int64, totalBytes: Int64) {
        modelId.withCString { modelIdPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_MODEL_DOWNLOAD_PROGRESS
            eventData.data.model_download.model_id = modelIdPtr
            eventData.data.model_download.progress = progress
            eventData.data.model_download.bytes_downloaded = bytesDownloaded
            eventData.data.model_download.total_bytes = totalBytes
            eventData.data.model_download.duration_ms = 0
            eventData.data.model_download.error_code = RAC_SUCCESS
            eventData.data.model_download.error_message = nil
            rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_PROGRESS, &eventData)
        }
    }

    /// Emit download completed event via C++
    public static func emitDownloadCompleted(modelId: String, durationMs: Double, sizeBytes: Int64) {
        modelId.withCString { modelIdPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_MODEL_DOWNLOAD_COMPLETED
            eventData.data.model_download.model_id = modelIdPtr
            eventData.data.model_download.duration_ms = durationMs
            eventData.data.model_download.size_bytes = sizeBytes
            eventData.data.model_download.progress = 100
            eventData.data.model_download.error_code = RAC_SUCCESS
            eventData.data.model_download.error_message = nil
            rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_COMPLETED, &eventData)
        }
    }

    /// Emit download failed event via C++
    public static func emitDownloadFailed(modelId: String, error: SDKError) {
        modelId.withCString { modelIdPtr in
            error.message.withCString { errorMsgPtr in
                var eventData = rac_analytics_event_data_t()
                eventData.type = RAC_EVENT_MODEL_DOWNLOAD_FAILED
                eventData.data.model_download.model_id = modelIdPtr
                eventData.data.model_download.error_code = RAC_ERROR_UNKNOWN
                eventData.data.model_download.error_message = errorMsgPtr
                eventData.data.model_download.progress = 0
                eventData.data.model_download.duration_ms = 0
                rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_FAILED, &eventData)
            }
        }
    }

    /// Emit download cancelled event via C++
    public static func emitDownloadCancelled(modelId: String) {
        modelId.withCString { modelIdPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_MODEL_DOWNLOAD_CANCELLED
            eventData.data.model_download.model_id = modelIdPtr
            eventData.data.model_download.error_code = RAC_SUCCESS
            eventData.data.model_download.error_message = nil
            rac_analytics_event_emit(RAC_EVENT_MODEL_DOWNLOAD_CANCELLED, &eventData)
        }
    }

    // MARK: - Extraction Events

    /// Emit extraction started event via C++
    public static func emitExtractionStarted(modelId: String, archiveType: String) {
        modelId.withCString { modelIdPtr in
            archiveType.withCString { archiveTypePtr in
                var eventData = rac_analytics_event_data_t()
                eventData.type = RAC_EVENT_MODEL_EXTRACTION_STARTED
                eventData.data.model_download.model_id = modelIdPtr
                eventData.data.model_download.archive_type = archiveTypePtr
                eventData.data.model_download.progress = 0
                eventData.data.model_download.error_code = RAC_SUCCESS
                eventData.data.model_download.error_message = nil
                rac_analytics_event_emit(RAC_EVENT_MODEL_EXTRACTION_STARTED, &eventData)
            }
        }
    }

    /// Emit extraction progress event via C++
    public static func emitExtractionProgress(modelId: String, progress: Double) {
        modelId.withCString { modelIdPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_MODEL_EXTRACTION_PROGRESS
            eventData.data.model_download.model_id = modelIdPtr
            eventData.data.model_download.progress = progress
            eventData.data.model_download.error_code = RAC_SUCCESS
            eventData.data.model_download.error_message = nil
            rac_analytics_event_emit(RAC_EVENT_MODEL_EXTRACTION_PROGRESS, &eventData)
        }
    }

    /// Emit extraction completed event via C++
    public static func emitExtractionCompleted(modelId: String, durationMs: Double) {
        modelId.withCString { modelIdPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_MODEL_EXTRACTION_COMPLETED
            eventData.data.model_download.model_id = modelIdPtr
            eventData.data.model_download.duration_ms = durationMs
            eventData.data.model_download.progress = 100
            eventData.data.model_download.error_code = RAC_SUCCESS
            eventData.data.model_download.error_message = nil
            rac_analytics_event_emit(RAC_EVENT_MODEL_EXTRACTION_COMPLETED, &eventData)
        }
    }

    /// Emit extraction failed event via C++
    public static func emitExtractionFailed(modelId: String, error: SDKError) {
        modelId.withCString { modelIdPtr in
            error.message.withCString { errorMsgPtr in
                var eventData = rac_analytics_event_data_t()
                eventData.type = RAC_EVENT_MODEL_EXTRACTION_FAILED
                eventData.data.model_download.model_id = modelIdPtr
                eventData.data.model_download.error_code = RAC_ERROR_UNKNOWN
                eventData.data.model_download.error_message = errorMsgPtr
                rac_analytics_event_emit(RAC_EVENT_MODEL_EXTRACTION_FAILED, &eventData)
            }
        }
    }

    // MARK: - Model Deleted Event

    /// Emit model deleted event via C++
    public static func emitModelDeleted(modelId: String) {
        modelId.withCString { modelIdPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_MODEL_DELETED
            eventData.data.model_download.model_id = modelIdPtr
            eventData.data.model_download.error_code = RAC_SUCCESS
            eventData.data.model_download.error_message = nil
            rac_analytics_event_emit(RAC_EVENT_MODEL_DELETED, &eventData)
        }
    }

    // MARK: - SDK Lifecycle Events

    /// Emit SDK init started event via C++
    public static func emitSDKInitStarted() {
        var eventData = rac_analytics_event_data_t()
        eventData.type = RAC_EVENT_SDK_INIT_STARTED
        eventData.data.sdk_lifecycle.duration_ms = 0
        eventData.data.sdk_lifecycle.count = 0
        eventData.data.sdk_lifecycle.error_code = RAC_SUCCESS
        eventData.data.sdk_lifecycle.error_message = nil
        rac_analytics_event_emit(RAC_EVENT_SDK_INIT_STARTED, &eventData)
    }

    /// Emit SDK init completed event via C++
    public static func emitSDKInitCompleted(durationMs: Double) {
        var eventData = rac_analytics_event_data_t()
        eventData.type = RAC_EVENT_SDK_INIT_COMPLETED
        eventData.data.sdk_lifecycle.duration_ms = durationMs
        eventData.data.sdk_lifecycle.count = 0
        eventData.data.sdk_lifecycle.error_code = RAC_SUCCESS
        eventData.data.sdk_lifecycle.error_message = nil
        rac_analytics_event_emit(RAC_EVENT_SDK_INIT_COMPLETED, &eventData)
    }

    /// Emit SDK init failed event via C++
    public static func emitSDKInitFailed(error: SDKError) {
        error.message.withCString { errorMsgPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_SDK_INIT_FAILED
            eventData.data.sdk_lifecycle.duration_ms = 0
            eventData.data.sdk_lifecycle.count = 0
            eventData.data.sdk_lifecycle.error_code = RAC_ERROR_UNKNOWN
            eventData.data.sdk_lifecycle.error_message = errorMsgPtr
            rac_analytics_event_emit(RAC_EVENT_SDK_INIT_FAILED, &eventData)
        }
    }

    /// Emit SDK models loaded event via C++
    public static func emitSDKModelsLoaded(count: Int) {
        var eventData = rac_analytics_event_data_t()
        eventData.type = RAC_EVENT_SDK_MODELS_LOADED
        eventData.data.sdk_lifecycle.duration_ms = 0
        eventData.data.sdk_lifecycle.count = Int32(count)
        eventData.data.sdk_lifecycle.error_code = RAC_SUCCESS
        eventData.data.sdk_lifecycle.error_message = nil
        rac_analytics_event_emit(RAC_EVENT_SDK_MODELS_LOADED, &eventData)
    }

    // MARK: - Storage Events

    /// Emit storage cache cleared event via C++
    public static func emitStorageCacheCleared(freedBytes: Int64) {
        var eventData = rac_analytics_event_data_t()
        eventData.type = RAC_EVENT_STORAGE_CACHE_CLEARED
        eventData.data.storage.freed_bytes = freedBytes
        eventData.data.storage.error_code = RAC_SUCCESS
        eventData.data.storage.error_message = nil
        rac_analytics_event_emit(RAC_EVENT_STORAGE_CACHE_CLEARED, &eventData)
    }

    /// Emit storage cache clear failed event via C++
    public static func emitStorageCacheClearFailed(error: SDKError) {
        error.message.withCString { errorMsgPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_STORAGE_CACHE_CLEAR_FAILED
            eventData.data.storage.freed_bytes = 0
            eventData.data.storage.error_code = RAC_ERROR_UNKNOWN
            eventData.data.storage.error_message = errorMsgPtr
            rac_analytics_event_emit(RAC_EVENT_STORAGE_CACHE_CLEAR_FAILED, &eventData)
        }
    }

    /// Emit storage temp cleaned event via C++
    public static func emitStorageTempCleaned(freedBytes: Int64) {
        var eventData = rac_analytics_event_data_t()
        eventData.type = RAC_EVENT_STORAGE_TEMP_CLEANED
        eventData.data.storage.freed_bytes = freedBytes
        eventData.data.storage.error_code = RAC_SUCCESS
        eventData.data.storage.error_message = nil
        rac_analytics_event_emit(RAC_EVENT_STORAGE_TEMP_CLEANED, &eventData)
    }

    // MARK: - Voice Agent / Pipeline Events

    /// Emit voice agent turn started event via C++
    public static func emitVoiceAgentTurnStarted() {
        var eventData = rac_analytics_event_data_t()
        eventData.type = RAC_EVENT_VOICE_AGENT_TURN_STARTED
        rac_analytics_event_emit(RAC_EVENT_VOICE_AGENT_TURN_STARTED, &eventData)
    }

    /// Emit voice agent turn completed event via C++
    public static func emitVoiceAgentTurnCompleted(durationMs: Double) {
        var eventData = rac_analytics_event_data_t()
        eventData.type = RAC_EVENT_VOICE_AGENT_TURN_COMPLETED
        eventData.data.sdk_lifecycle.duration_ms = durationMs
        eventData.data.sdk_lifecycle.error_code = RAC_SUCCESS
        eventData.data.sdk_lifecycle.error_message = nil
        rac_analytics_event_emit(RAC_EVENT_VOICE_AGENT_TURN_COMPLETED, &eventData)
    }

    /// Emit voice agent turn failed event via C++
    public static func emitVoiceAgentTurnFailed(error: SDKError) {
        error.message.withCString { errorMsgPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_VOICE_AGENT_TURN_FAILED
            eventData.data.sdk_lifecycle.duration_ms = 0
            eventData.data.sdk_lifecycle.count = 0
            eventData.data.sdk_lifecycle.error_code = RAC_ERROR_UNKNOWN
            eventData.data.sdk_lifecycle.error_message = errorMsgPtr
            rac_analytics_event_emit(RAC_EVENT_VOICE_AGENT_TURN_FAILED, &eventData)
        }
    }

    // MARK: - Device Events

    /// Emit device registered event via C++
    public static func emitDeviceRegistered(deviceId: String) {
        deviceId.withCString { deviceIdPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_DEVICE_REGISTERED
            eventData.data.device.device_id = deviceIdPtr
            eventData.data.device.error_code = RAC_SUCCESS
            eventData.data.device.error_message = nil
            rac_analytics_event_emit(RAC_EVENT_DEVICE_REGISTERED, &eventData)
        }
    }

    /// Emit device registration failed event via C++
    public static func emitDeviceRegistrationFailed(error: SDKError) {
        error.message.withCString { errorMsgPtr in
            var eventData = rac_analytics_event_data_t()
            eventData.type = RAC_EVENT_DEVICE_REGISTRATION_FAILED
            eventData.data.device.device_id = nil
            eventData.data.device.error_code = RAC_ERROR_UNKNOWN
            eventData.data.device.error_message = errorMsgPtr
            rac_analytics_event_emit(RAC_EVENT_DEVICE_REGISTRATION_FAILED, &eventData)
        }
    }

    // MARK: - SDK Error Events

    /// Emit SDK error event via C++
    public static func emitSDKError(error: SDKError, operation: String, context: String? = nil) {
        error.message.withCString { errorMsgPtr in
            operation.withCString { operationPtr in
                var eventData = rac_analytics_event_data_t()
                eventData.type = RAC_EVENT_SDK_ERROR
                eventData.data.sdk_error.error_code = RAC_ERROR_UNKNOWN
                eventData.data.sdk_error.error_message = errorMsgPtr
                eventData.data.sdk_error.operation = operationPtr

                if let context = context {
                    context.withCString { contextPtr in
                        eventData.data.sdk_error.context = contextPtr
                        rac_analytics_event_emit(RAC_EVENT_SDK_ERROR, &eventData)
                    }
                } else {
                    eventData.data.sdk_error.context = nil
                    rac_analytics_event_emit(RAC_EVENT_SDK_ERROR, &eventData)
                }
            }
        }
    }
}
