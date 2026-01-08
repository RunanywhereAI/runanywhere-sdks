/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Events extension for CppBridge.
 * Provides analytics event callback registration for C++ core.
 *
 * Follows iOS CppBridge+Telemetry.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Events bridge that registers analytics event callbacks with C++ core.
 *
 * The C++ core generates analytics events during SDK operations (model loading,
 * inference, errors, etc.). This extension registers a callback to receive
 * those events and route them to the Kotlin analytics system.
 *
 * Usage:
 * - Called during Phase 1 initialization in [CppBridge.initialize]
 * - Must be registered after [CppBridgePlatformAdapter] is registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - Event callback is called from C++ threads, must be thread-safe
 */
object CppBridgeEvents {
    /**
     * Event type constants matching C++ rac_analytics_events.h RAC_EVENT_* values.
     * These values MUST match the C++ enum exactly for proper event routing.
     */
    object EventType {
        // LLM Events (100-199)
        const val LLM_MODEL_LOAD_STARTED = 100
        const val LLM_MODEL_LOAD_COMPLETED = 101
        const val LLM_MODEL_LOAD_FAILED = 102
        const val LLM_MODEL_UNLOADED = 103
        const val LLM_GENERATION_STARTED = 110
        const val LLM_GENERATION_COMPLETED = 111
        const val LLM_GENERATION_FAILED = 112
        const val LLM_FIRST_TOKEN = 113
        const val LLM_STREAMING_UPDATE = 114

        // STT Events (200-299)
        const val STT_MODEL_LOAD_STARTED = 200
        const val STT_MODEL_LOAD_COMPLETED = 201
        const val STT_MODEL_LOAD_FAILED = 202
        const val STT_MODEL_UNLOADED = 203
        const val STT_TRANSCRIPTION_STARTED = 210
        const val STT_TRANSCRIPTION_COMPLETED = 211
        const val STT_TRANSCRIPTION_FAILED = 212
        const val STT_PARTIAL_TRANSCRIPT = 213

        // TTS Events (300-399)
        const val TTS_VOICE_LOAD_STARTED = 300
        const val TTS_VOICE_LOAD_COMPLETED = 301
        const val TTS_VOICE_LOAD_FAILED = 302
        const val TTS_VOICE_UNLOADED = 303
        const val TTS_SYNTHESIS_STARTED = 310
        const val TTS_SYNTHESIS_COMPLETED = 311
        const val TTS_SYNTHESIS_FAILED = 312
        const val TTS_SYNTHESIS_CHUNK = 313

        // VAD Events (400-499)
        const val VAD_STARTED = 400
        const val VAD_STOPPED = 401
        const val VAD_SPEECH_STARTED = 402
        const val VAD_SPEECH_ENDED = 403
        const val VAD_PAUSED = 404
        const val VAD_RESUMED = 405

        // VoiceAgent Events (500-599)
        const val VOICE_AGENT_TURN_STARTED = 500
        const val VOICE_AGENT_TURN_COMPLETED = 501
        const val VOICE_AGENT_TURN_FAILED = 502
        const val VOICE_AGENT_STT_STATE_CHANGED = 510
        const val VOICE_AGENT_LLM_STATE_CHANGED = 511
        const val VOICE_AGENT_TTS_STATE_CHANGED = 512
        const val VOICE_AGENT_ALL_READY = 513

        // SDK Lifecycle Events (600-699)
        const val SDK_INIT_STARTED = 600
        const val SDK_INIT_COMPLETED = 601
        const val SDK_INIT_FAILED = 602
        const val SDK_MODELS_LOADED = 603

        // Model Download Events (700-719)
        const val MODEL_DOWNLOAD_STARTED = 700
        const val MODEL_DOWNLOAD_PROGRESS = 701
        const val MODEL_DOWNLOAD_COMPLETED = 702
        const val MODEL_DOWNLOAD_FAILED = 703
        const val MODEL_DOWNLOAD_CANCELLED = 704

        // Model Extraction Events (710-719)
        const val MODEL_EXTRACTION_STARTED = 710
        const val MODEL_EXTRACTION_PROGRESS = 711
        const val MODEL_EXTRACTION_COMPLETED = 712
        const val MODEL_EXTRACTION_FAILED = 713

        // Model Deletion Events (720-729)
        const val MODEL_DELETED = 720

        // Storage Events (800-899)
        const val STORAGE_CACHE_CLEARED = 800
        const val STORAGE_CACHE_CLEAR_FAILED = 801
        const val STORAGE_TEMP_CLEANED = 802

        // Device Events (900-999)
        const val DEVICE_REGISTERED = 900
        const val DEVICE_REGISTRATION_FAILED = 901

        // Network Events (1000-1099)
        const val NETWORK_CONNECTIVITY_CHANGED = 1000

        // Error Events (1100-1199)
        const val SDK_ERROR = 1100

        // Framework Events (1200-1299)
        const val FRAMEWORK_MODELS_REQUESTED = 1200
        const val FRAMEWORK_MODELS_RETRIEVED = 1201

        /**
         * Get a human-readable name for the event type.
         */
        fun getName(type: Int): String =
            when (type) {
                // LLM
                LLM_MODEL_LOAD_STARTED -> "LLM_MODEL_LOAD_STARTED"
                LLM_MODEL_LOAD_COMPLETED -> "LLM_MODEL_LOAD_COMPLETED"
                LLM_MODEL_LOAD_FAILED -> "LLM_MODEL_LOAD_FAILED"
                LLM_MODEL_UNLOADED -> "LLM_MODEL_UNLOADED"
                LLM_GENERATION_STARTED -> "LLM_GENERATION_STARTED"
                LLM_GENERATION_COMPLETED -> "LLM_GENERATION_COMPLETED"
                LLM_GENERATION_FAILED -> "LLM_GENERATION_FAILED"
                LLM_FIRST_TOKEN -> "LLM_FIRST_TOKEN"
                LLM_STREAMING_UPDATE -> "LLM_STREAMING_UPDATE"
                // STT
                STT_MODEL_LOAD_STARTED -> "STT_MODEL_LOAD_STARTED"
                STT_MODEL_LOAD_COMPLETED -> "STT_MODEL_LOAD_COMPLETED"
                STT_MODEL_LOAD_FAILED -> "STT_MODEL_LOAD_FAILED"
                STT_MODEL_UNLOADED -> "STT_MODEL_UNLOADED"
                STT_TRANSCRIPTION_STARTED -> "STT_TRANSCRIPTION_STARTED"
                STT_TRANSCRIPTION_COMPLETED -> "STT_TRANSCRIPTION_COMPLETED"
                STT_TRANSCRIPTION_FAILED -> "STT_TRANSCRIPTION_FAILED"
                STT_PARTIAL_TRANSCRIPT -> "STT_PARTIAL_TRANSCRIPT"
                // TTS
                TTS_VOICE_LOAD_STARTED -> "TTS_VOICE_LOAD_STARTED"
                TTS_VOICE_LOAD_COMPLETED -> "TTS_VOICE_LOAD_COMPLETED"
                TTS_VOICE_LOAD_FAILED -> "TTS_VOICE_LOAD_FAILED"
                TTS_VOICE_UNLOADED -> "TTS_VOICE_UNLOADED"
                TTS_SYNTHESIS_STARTED -> "TTS_SYNTHESIS_STARTED"
                TTS_SYNTHESIS_COMPLETED -> "TTS_SYNTHESIS_COMPLETED"
                TTS_SYNTHESIS_FAILED -> "TTS_SYNTHESIS_FAILED"
                TTS_SYNTHESIS_CHUNK -> "TTS_SYNTHESIS_CHUNK"
                // VAD
                VAD_STARTED -> "VAD_STARTED"
                VAD_STOPPED -> "VAD_STOPPED"
                VAD_SPEECH_STARTED -> "VAD_SPEECH_STARTED"
                VAD_SPEECH_ENDED -> "VAD_SPEECH_ENDED"
                VAD_PAUSED -> "VAD_PAUSED"
                VAD_RESUMED -> "VAD_RESUMED"
                // Voice Agent
                VOICE_AGENT_TURN_STARTED -> "VOICE_AGENT_TURN_STARTED"
                VOICE_AGENT_TURN_COMPLETED -> "VOICE_AGENT_TURN_COMPLETED"
                VOICE_AGENT_TURN_FAILED -> "VOICE_AGENT_TURN_FAILED"
                VOICE_AGENT_STT_STATE_CHANGED -> "VOICE_AGENT_STT_STATE_CHANGED"
                VOICE_AGENT_LLM_STATE_CHANGED -> "VOICE_AGENT_LLM_STATE_CHANGED"
                VOICE_AGENT_TTS_STATE_CHANGED -> "VOICE_AGENT_TTS_STATE_CHANGED"
                VOICE_AGENT_ALL_READY -> "VOICE_AGENT_ALL_READY"
                // SDK Lifecycle
                SDK_INIT_STARTED -> "SDK_INIT_STARTED"
                SDK_INIT_COMPLETED -> "SDK_INIT_COMPLETED"
                SDK_INIT_FAILED -> "SDK_INIT_FAILED"
                SDK_MODELS_LOADED -> "SDK_MODELS_LOADED"
                // Download
                MODEL_DOWNLOAD_STARTED -> "MODEL_DOWNLOAD_STARTED"
                MODEL_DOWNLOAD_PROGRESS -> "MODEL_DOWNLOAD_PROGRESS"
                MODEL_DOWNLOAD_COMPLETED -> "MODEL_DOWNLOAD_COMPLETED"
                MODEL_DOWNLOAD_FAILED -> "MODEL_DOWNLOAD_FAILED"
                MODEL_DOWNLOAD_CANCELLED -> "MODEL_DOWNLOAD_CANCELLED"
                // Extraction
                MODEL_EXTRACTION_STARTED -> "MODEL_EXTRACTION_STARTED"
                MODEL_EXTRACTION_PROGRESS -> "MODEL_EXTRACTION_PROGRESS"
                MODEL_EXTRACTION_COMPLETED -> "MODEL_EXTRACTION_COMPLETED"
                MODEL_EXTRACTION_FAILED -> "MODEL_EXTRACTION_FAILED"
                // Deletion
                MODEL_DELETED -> "MODEL_DELETED"
                // Storage
                STORAGE_CACHE_CLEARED -> "STORAGE_CACHE_CLEARED"
                STORAGE_CACHE_CLEAR_FAILED -> "STORAGE_CACHE_CLEAR_FAILED"
                STORAGE_TEMP_CLEANED -> "STORAGE_TEMP_CLEANED"
                // Device
                DEVICE_REGISTERED -> "DEVICE_REGISTERED"
                DEVICE_REGISTRATION_FAILED -> "DEVICE_REGISTRATION_FAILED"
                // Network
                NETWORK_CONNECTIVITY_CHANGED -> "NETWORK_CONNECTIVITY_CHANGED"
                // Error
                SDK_ERROR -> "SDK_ERROR"
                // Framework
                FRAMEWORK_MODELS_REQUESTED -> "FRAMEWORK_MODELS_REQUESTED"
                FRAMEWORK_MODELS_RETRIEVED -> "FRAMEWORK_MODELS_RETRIEVED"
                else -> "UNKNOWN($type)"
            }
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeEvents"

    /**
     * Optional listener for receiving analytics events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var eventListener: AnalyticsEventListener? = null

    /**
     * Listener interface for receiving analytics events from C++ core.
     */
    interface AnalyticsEventListener {
        /**
         * Called when an analytics event is received from C++ core.
         *
         * @param eventType The type of event (see [EventType] constants)
         * @param eventName The name/category of the event
         * @param eventData JSON-encoded event data, or null if no data
         * @param timestampMs The timestamp when the event occurred (milliseconds since epoch)
         */
        fun onEvent(eventType: Int, eventName: String, eventData: String?, timestampMs: Long)
    }

    /**
     * Register the analytics event callback with C++ core.
     *
     * This connects C++ analytics events to the telemetry manager for batching and HTTP transport.
     * Events from LLM/STT/TTS operations flow: C++ emit → callback → telemetry manager → HTTP
     *
     * @param telemetryHandle Handle to the telemetry manager (from racTelemetryManagerCreate)
     * @return true if registration succeeded, false otherwise
     */
    fun register(telemetryHandle: Long): Boolean {
        synchronized(lock) {
            if (isRegistered) {
                return true
            }

            if (telemetryHandle == 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Cannot register analytics callback: telemetry handle is null",
                )
                return false
            }

            // Register C++ analytics callback that routes to telemetry manager
            // This mirrors Swift's Events.register() -> rac_analytics_events_set_callback()
            val result = RunAnywhereBridge.racAnalyticsEventsSetCallback(telemetryHandle)
            if (result == 0) { // RAC_SUCCESS
                isRegistered = true
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Analytics events callback registered with telemetry manager",
                )
                return true
            } else {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Failed to register analytics callback: error $result",
                )
                return false
            }
        }
    }

    /**
     * Unregister the analytics event callback.
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }
            // Unregister by passing 0 (null handle)
            RunAnywhereBridge.racAnalyticsEventsSetCallback(0L)
            isRegistered = false
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Analytics events callback unregistered",
            )
        }
    }

    /**
     * Check if the events callback is registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // EVENT CALLBACK
    // ========================================================================

    /**
     * Event callback invoked by C++ core when an analytics event occurs.
     *
     * Routes events to the registered [AnalyticsEventListener] if one is set.
     *
     * @param eventType The type of event (see [EventType] constants)
     * @param eventName The name/category of the event
     * @param eventData JSON-encoded event data, or null if no data
     * @param timestampMs The timestamp when the event occurred (milliseconds since epoch)
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun eventCallback(eventType: Int, eventName: String, eventData: String?, timestampMs: Long) {
        // Log the event for debugging (at trace level to avoid noise)
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.TRACE,
            TAG,
            "Event: ${EventType.getName(eventType)} - $eventName",
        )

        // Route to the registered listener
        try {
            eventListener?.onEvent(eventType, eventName, eventData, timestampMs)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Error in event listener: ${e.message}",
            )
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Track a custom event programmatically.
     *
     * This allows Kotlin code to emit events that will be processed
     * by the same analytics pipeline as C++ events.
     *
     * @param eventType The type of event (see [EventType] constants)
     * @param eventName The name/category of the event
     * @param eventData Optional JSON-encoded event data
     */
    fun trackEvent(eventType: Int, eventName: String, eventData: String? = null) {
        val timestampMs = System.currentTimeMillis()
        eventCallback(eventType, eventName, eventData, timestampMs)
    }

    /**
     * Track an error event.
     *
     * @param errorMessage The error message
     * @param operation The operation that failed (e.g., "model_load")
     * @param context Additional context (optional)
     */
    fun trackError(errorMessage: String, operation: String = "unknown", context: String? = null) {
        emitSDKError(errorMessage, operation, context)
    }

    /**
     * Track a warning event (logs only, not tracked via telemetry).
     *
     * @param warningMessage The warning message
     * @param warningData Optional context data
     */
    fun trackWarning(warningMessage: String, warningData: String? = null) {
        val message =
            if (warningData != null) {
                "$warningMessage [context: $warningData]"
            } else {
                warningMessage
            }
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.WARN,
            TAG,
            message,
        )
    }

    // ========================================================================
    // DOWNLOAD EVENT HELPERS (mirrors Swift CppBridge+Telemetry.swift)
    // ========================================================================

    /**
     * Emit download started event via C++.
     *
     * @param modelId The model being downloaded
     * @param totalBytes Expected total bytes (0 if unknown)
     */
    fun emitDownloadStarted(modelId: String, totalBytes: Long = 0) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_DOWNLOAD_STARTED,
            modelId,
            0.0, // progress
            0, // bytesDownloaded
            totalBytes,
            0.0, // durationMs
            0, // sizeBytes
            null, // archiveType
            0, // errorCode
            null, // errorMessage
        )
    }

    /**
     * Emit download progress event via C++.
     */
    fun emitDownloadProgress(modelId: String, progress: Double, bytesDownloaded: Long, totalBytes: Long) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_DOWNLOAD_PROGRESS,
            modelId,
            progress,
            bytesDownloaded,
            totalBytes,
            0.0, // durationMs
            0, // sizeBytes
            null, // archiveType
            0, // errorCode
            null, // errorMessage
        )
    }

    /**
     * Emit download completed event via C++.
     */
    fun emitDownloadCompleted(modelId: String, durationMs: Double, sizeBytes: Long) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_DOWNLOAD_COMPLETED,
            modelId,
            100.0, // progress
            sizeBytes, // bytesDownloaded
            sizeBytes, // totalBytes
            durationMs,
            sizeBytes,
            null, // archiveType
            0, // errorCode (RAC_SUCCESS)
            null, // errorMessage
        )
    }

    /**
     * Emit download failed event via C++.
     */
    fun emitDownloadFailed(modelId: String, errorMessage: String) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_DOWNLOAD_FAILED,
            modelId,
            0.0, // progress
            0, // bytesDownloaded
            0, // totalBytes
            0.0, // durationMs
            0, // sizeBytes
            null, // archiveType
            -5, // errorCode (RAC_ERROR_OPERATION_FAILED)
            errorMessage,
        )
    }

    /**
     * Emit download cancelled event via C++.
     */
    fun emitDownloadCancelled(modelId: String) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_DOWNLOAD_CANCELLED,
            modelId,
            0.0,
            0,
            0,
            0.0,
            0,
            null,
            0, // RAC_SUCCESS
            null,
        )
    }

    // ========================================================================
    // EXTRACTION EVENT HELPERS
    // ========================================================================

    /**
     * Emit extraction started event via C++.
     */
    fun emitExtractionStarted(modelId: String, archiveType: String) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_EXTRACTION_STARTED,
            modelId,
            0.0,
            0,
            0,
            0.0,
            0,
            archiveType,
            0,
            null,
        )
    }

    /**
     * Emit extraction progress event via C++.
     */
    fun emitExtractionProgress(modelId: String, progress: Double) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_EXTRACTION_PROGRESS,
            modelId,
            progress,
            0,
            0,
            0.0,
            0,
            null,
            0,
            null,
        )
    }

    /**
     * Emit extraction completed event via C++.
     */
    fun emitExtractionCompleted(modelId: String, durationMs: Double) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_EXTRACTION_COMPLETED,
            modelId,
            100.0,
            0,
            0,
            durationMs,
            0,
            null,
            0,
            null,
        )
    }

    /**
     * Emit extraction failed event via C++.
     */
    fun emitExtractionFailed(modelId: String, errorMessage: String) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_EXTRACTION_FAILED,
            modelId,
            0.0,
            0,
            0,
            0.0,
            0,
            null,
            -5,
            errorMessage,
        )
    }

    // ========================================================================
    // MODEL DELETED EVENT
    // ========================================================================

    /**
     * Emit model deleted event via C++.
     */
    fun emitModelDeleted(modelId: String) {
        RunAnywhereBridge.racAnalyticsEventEmitDownload(
            EventType.MODEL_DELETED,
            modelId,
            0.0,
            0,
            0,
            0.0,
            0,
            null,
            0,
            null,
        )
    }

    // ========================================================================
    // SDK LIFECYCLE EVENTS
    // ========================================================================

    /**
     * Emit SDK init started event via C++.
     */
    fun emitSDKInitStarted() {
        RunAnywhereBridge.racAnalyticsEventEmitSdkLifecycle(
            EventType.SDK_INIT_STARTED,
            0.0, // durationMs
            0, // count
            0, // errorCode
            null, // errorMessage
        )
    }

    /**
     * Emit SDK init completed event via C++.
     */
    fun emitSDKInitCompleted(durationMs: Double) {
        RunAnywhereBridge.racAnalyticsEventEmitSdkLifecycle(
            EventType.SDK_INIT_COMPLETED,
            durationMs,
            0,
            0,
            null,
        )
    }

    /**
     * Emit SDK init failed event via C++.
     */
    fun emitSDKInitFailed(errorMessage: String) {
        RunAnywhereBridge.racAnalyticsEventEmitSdkLifecycle(
            EventType.SDK_INIT_FAILED,
            0.0,
            0,
            -5, // RAC_ERROR_OPERATION_FAILED
            errorMessage,
        )
    }

    /**
     * Emit SDK models loaded event via C++.
     */
    fun emitSDKModelsLoaded(count: Int) {
        RunAnywhereBridge.racAnalyticsEventEmitSdkLifecycle(
            EventType.SDK_MODELS_LOADED,
            0.0,
            count,
            0,
            null,
        )
    }

    // ========================================================================
    // STORAGE EVENTS
    // ========================================================================

    /**
     * Emit storage cache cleared event via C++.
     */
    fun emitStorageCacheCleared(freedBytes: Long) {
        RunAnywhereBridge.racAnalyticsEventEmitStorage(
            EventType.STORAGE_CACHE_CLEARED,
            freedBytes,
            0,
            null,
        )
    }

    /**
     * Emit storage cache clear failed event via C++.
     */
    fun emitStorageCacheClearFailed(errorMessage: String) {
        RunAnywhereBridge.racAnalyticsEventEmitStorage(
            EventType.STORAGE_CACHE_CLEAR_FAILED,
            0,
            -5,
            errorMessage,
        )
    }

    /**
     * Emit storage temp cleaned event via C++.
     */
    fun emitStorageTempCleaned(freedBytes: Long) {
        RunAnywhereBridge.racAnalyticsEventEmitStorage(
            EventType.STORAGE_TEMP_CLEANED,
            freedBytes,
            0,
            null,
        )
    }

    // ========================================================================
    // VOICE AGENT / PIPELINE EVENTS
    // ========================================================================

    /**
     * Emit voice agent turn started event via C++.
     */
    fun emitVoiceAgentTurnStarted() {
        RunAnywhereBridge.racAnalyticsEventEmitSdkLifecycle(
            EventType.VOICE_AGENT_TURN_STARTED,
            0.0,
            0,
            0,
            null,
        )
    }

    /**
     * Emit voice agent turn completed event via C++.
     */
    fun emitVoiceAgentTurnCompleted(durationMs: Double) {
        RunAnywhereBridge.racAnalyticsEventEmitSdkLifecycle(
            EventType.VOICE_AGENT_TURN_COMPLETED,
            durationMs,
            0,
            0,
            null,
        )
    }

    /**
     * Emit voice agent turn failed event via C++.
     */
    fun emitVoiceAgentTurnFailed(errorMessage: String) {
        RunAnywhereBridge.racAnalyticsEventEmitSdkLifecycle(
            EventType.VOICE_AGENT_TURN_FAILED,
            0.0,
            0,
            -5,
            errorMessage,
        )
    }

    // ========================================================================
    // DEVICE EVENTS
    // ========================================================================

    /**
     * Emit device registered event via C++.
     */
    fun emitDeviceRegistered(deviceId: String) {
        RunAnywhereBridge.racAnalyticsEventEmitDevice(
            EventType.DEVICE_REGISTERED,
            deviceId,
            0,
            null,
        )
    }

    /**
     * Emit device registration failed event via C++.
     */
    fun emitDeviceRegistrationFailed(errorMessage: String) {
        RunAnywhereBridge.racAnalyticsEventEmitDevice(
            EventType.DEVICE_REGISTRATION_FAILED,
            null,
            -5,
            errorMessage,
        )
    }

    // ========================================================================
    // SDK ERROR EVENTS
    // ========================================================================

    /**
     * Emit SDK error event via C++.
     */
    fun emitSDKError(errorMessage: String, operation: String, context: String? = null) {
        RunAnywhereBridge.racAnalyticsEventEmitSdkError(
            EventType.SDK_ERROR,
            -5, // RAC_ERROR_OPERATION_FAILED
            errorMessage,
            operation,
            context,
        )
    }

    // ========================================================================
    // NETWORK EVENTS
    // ========================================================================

    /**
     * Emit network connectivity changed event via C++.
     */
    fun emitNetworkConnectivityChanged(isOnline: Boolean) {
        RunAnywhereBridge.racAnalyticsEventEmitNetwork(
            EventType.NETWORK_CONNECTIVITY_CHANGED,
            isOnline,
        )
    }

    // ========================================================================
    // LLM MODEL EVENTS (mirrors Swift CppBridge+Telemetry.swift)
    // ========================================================================

    /**
     * Inference framework constants matching C++ rac_inference_framework_t.
     */
    object Framework {
        const val UNKNOWN = 0
        const val LLAMACPP = 1
        const val ONNX = 2
        const val MLX = 3
        const val COREML = 4
        const val FOUNDATION = 5
        const val SYSTEM = 6
    }

    /**
     * Emit LLM model load started event via C++.
     */
    fun emitLlmModelLoadStarted(modelId: String, modelName: String?, framework: Int = Framework.UNKNOWN) {
        RunAnywhereBridge.racAnalyticsEventEmitLlmModel(
            EventType.LLM_MODEL_LOAD_STARTED,
            modelId,
            modelName,
            0, // modelSizeBytes
            0.0, // durationMs
            framework,
            0,
            null,
        )
    }

    /**
     * Emit LLM model load completed event via C++.
     */
    fun emitLlmModelLoadCompleted(
        modelId: String,
        modelName: String?,
        modelSizeBytes: Long,
        durationMs: Double,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitLlmModel(
            EventType.LLM_MODEL_LOAD_COMPLETED,
            modelId,
            modelName,
            modelSizeBytes,
            durationMs,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit LLM model load failed event via C++.
     */
    fun emitLlmModelLoadFailed(
        modelId: String,
        modelName: String?,
        errorMessage: String,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitLlmModel(
            EventType.LLM_MODEL_LOAD_FAILED,
            modelId,
            modelName,
            0,
            0.0,
            framework,
            -5,
            errorMessage,
        )
    }

    /**
     * Emit LLM model unloaded event via C++.
     */
    fun emitLlmModelUnloaded(modelId: String, modelName: String?, framework: Int = Framework.UNKNOWN) {
        RunAnywhereBridge.racAnalyticsEventEmitLlmModel(
            EventType.LLM_MODEL_UNLOADED,
            modelId,
            modelName,
            0,
            0.0,
            framework,
            0,
            null,
        )
    }

    // ========================================================================
    // LLM GENERATION EVENTS
    // ========================================================================

    /**
     * Emit LLM generation started event via C++.
     */
    fun emitLlmGenerationStarted(
        generationId: String?,
        modelId: String?,
        modelName: String?,
        isStreaming: Boolean = false,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitLlmGeneration(
            EventType.LLM_GENERATION_STARTED,
            generationId,
            modelId,
            modelName,
            0,
            0,
            0.0,
            0.0, // tokens, duration, tokensPerSec
            isStreaming,
            0.0, // timeToFirstToken
            framework,
            0f,
            0,
            0, // temperature, maxTokens, contextLength
            0,
            null,
        )
    }

    /**
     * Emit LLM generation completed event via C++.
     */
    fun emitLlmGenerationCompleted(
        generationId: String?,
        modelId: String?,
        modelName: String?,
        inputTokens: Int,
        outputTokens: Int,
        durationMs: Double,
        tokensPerSecond: Double,
        isStreaming: Boolean = false,
        timeToFirstTokenMs: Double = 0.0,
        framework: Int = Framework.UNKNOWN,
        temperature: Float = 0f,
        maxTokens: Int = 0,
        contextLength: Int = 0,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitLlmGeneration(
            EventType.LLM_GENERATION_COMPLETED,
            generationId,
            modelId,
            modelName,
            inputTokens,
            outputTokens,
            durationMs,
            tokensPerSecond,
            isStreaming,
            timeToFirstTokenMs,
            framework,
            temperature,
            maxTokens,
            contextLength,
            0,
            null,
        )
    }

    /**
     * Emit LLM generation failed event via C++.
     */
    fun emitLlmGenerationFailed(
        generationId: String?,
        modelId: String?,
        modelName: String?,
        errorMessage: String,
        isStreaming: Boolean = false,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitLlmGeneration(
            EventType.LLM_GENERATION_FAILED,
            generationId,
            modelId,
            modelName,
            0,
            0,
            0.0,
            0.0,
            isStreaming,
            0.0,
            framework,
            0f,
            0,
            0,
            -5,
            errorMessage,
        )
    }

    /**
     * Emit LLM first token event via C++.
     */
    fun emitLlmFirstToken(
        generationId: String?,
        modelId: String?,
        timeToFirstTokenMs: Double,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitLlmGeneration(
            EventType.LLM_FIRST_TOKEN,
            generationId,
            modelId,
            null,
            0,
            0,
            0.0,
            0.0,
            true, // isStreaming
            timeToFirstTokenMs,
            framework,
            0f,
            0,
            0,
            0,
            null,
        )
    }

    // ========================================================================
    // STT MODEL EVENTS
    // ========================================================================

    /**
     * Emit STT model load started event via C++.
     */
    fun emitSttModelLoadStarted(modelId: String, modelName: String?, framework: Int = Framework.UNKNOWN) {
        RunAnywhereBridge.racAnalyticsEventEmitSttTranscription(
            EventType.STT_MODEL_LOAD_STARTED,
            null,
            modelId,
            modelName,
            null,
            0f,
            0.0,
            0.0,
            0,
            0,
            0.0,
            null,
            0,
            false,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit STT model load completed event via C++.
     */
    fun emitSttModelLoadCompleted(
        modelId: String,
        modelName: String?,
        durationMs: Double,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitSttTranscription(
            EventType.STT_MODEL_LOAD_COMPLETED,
            null,
            modelId,
            modelName,
            null,
            0f,
            durationMs,
            0.0,
            0,
            0,
            0.0,
            null,
            0,
            false,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit STT model load failed event via C++.
     */
    fun emitSttModelLoadFailed(
        modelId: String,
        modelName: String?,
        errorMessage: String,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitSttTranscription(
            EventType.STT_MODEL_LOAD_FAILED,
            null,
            modelId,
            modelName,
            null,
            0f,
            0.0,
            0.0,
            0,
            0,
            0.0,
            null,
            0,
            false,
            framework,
            -5,
            errorMessage,
        )
    }

    // ========================================================================
    // STT TRANSCRIPTION EVENTS
    // ========================================================================

    /**
     * Emit STT transcription started event via C++.
     */
    fun emitSttTranscriptionStarted(
        transcriptionId: String?,
        modelId: String?,
        modelName: String?,
        audioLengthMs: Double,
        audioSizeBytes: Int,
        isStreaming: Boolean = false,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitSttTranscription(
            EventType.STT_TRANSCRIPTION_STARTED,
            transcriptionId,
            modelId,
            modelName,
            null,
            0f,
            0.0,
            audioLengthMs,
            audioSizeBytes,
            0,
            0.0,
            null,
            0,
            isStreaming,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit STT transcription completed event via C++.
     */
    fun emitSttTranscriptionCompleted(
        transcriptionId: String?,
        modelId: String?,
        modelName: String?,
        text: String?,
        confidence: Float,
        durationMs: Double,
        audioLengthMs: Double,
        audioSizeBytes: Int,
        wordCount: Int,
        realTimeFactor: Double,
        language: String?,
        sampleRate: Int,
        isStreaming: Boolean = false,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitSttTranscription(
            EventType.STT_TRANSCRIPTION_COMPLETED,
            transcriptionId,
            modelId,
            modelName,
            text,
            confidence,
            durationMs,
            audioLengthMs,
            audioSizeBytes,
            wordCount,
            realTimeFactor,
            language,
            sampleRate,
            isStreaming,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit STT transcription failed event via C++.
     */
    fun emitSttTranscriptionFailed(
        transcriptionId: String?,
        modelId: String?,
        modelName: String?,
        errorMessage: String,
        isStreaming: Boolean = false,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitSttTranscription(
            EventType.STT_TRANSCRIPTION_FAILED,
            transcriptionId,
            modelId,
            modelName,
            null,
            0f,
            0.0,
            0.0,
            0,
            0,
            0.0,
            null,
            0,
            isStreaming,
            framework,
            -5,
            errorMessage,
        )
    }

    // ========================================================================
    // TTS MODEL EVENTS
    // ========================================================================

    /**
     * Emit TTS voice load started event via C++.
     */
    fun emitTtsVoiceLoadStarted(modelId: String, modelName: String?, framework: Int = Framework.UNKNOWN) {
        RunAnywhereBridge.racAnalyticsEventEmitTtsSynthesis(
            EventType.TTS_VOICE_LOAD_STARTED,
            null,
            modelId,
            modelName,
            0,
            0.0,
            0,
            0.0,
            0.0,
            0,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit TTS voice load completed event via C++.
     */
    fun emitTtsVoiceLoadCompleted(
        modelId: String,
        modelName: String?,
        durationMs: Double,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitTtsSynthesis(
            EventType.TTS_VOICE_LOAD_COMPLETED,
            null,
            modelId,
            modelName,
            0,
            0.0,
            0,
            durationMs,
            0.0,
            0,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit TTS voice load failed event via C++.
     */
    fun emitTtsVoiceLoadFailed(
        modelId: String,
        modelName: String?,
        errorMessage: String,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitTtsSynthesis(
            EventType.TTS_VOICE_LOAD_FAILED,
            null,
            modelId,
            modelName,
            0,
            0.0,
            0,
            0.0,
            0.0,
            0,
            framework,
            -5,
            errorMessage,
        )
    }

    // ========================================================================
    // TTS SYNTHESIS EVENTS
    // ========================================================================

    /**
     * Emit TTS synthesis started event via C++.
     */
    fun emitTtsSynthesisStarted(
        synthesisId: String?,
        modelId: String?,
        modelName: String?,
        characterCount: Int,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitTtsSynthesis(
            EventType.TTS_SYNTHESIS_STARTED,
            synthesisId,
            modelId,
            modelName,
            characterCount,
            0.0,
            0,
            0.0,
            0.0,
            0,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit TTS synthesis completed event via C++.
     */
    fun emitTtsSynthesisCompleted(
        synthesisId: String?,
        modelId: String?,
        modelName: String?,
        characterCount: Int,
        audioDurationMs: Double,
        audioSizeBytes: Int,
        processingDurationMs: Double,
        charactersPerSecond: Double,
        sampleRate: Int,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitTtsSynthesis(
            EventType.TTS_SYNTHESIS_COMPLETED,
            synthesisId,
            modelId,
            modelName,
            characterCount,
            audioDurationMs,
            audioSizeBytes,
            processingDurationMs,
            charactersPerSecond,
            sampleRate,
            framework,
            0,
            null,
        )
    }

    /**
     * Emit TTS synthesis failed event via C++.
     */
    fun emitTtsSynthesisFailed(
        synthesisId: String?,
        modelId: String?,
        modelName: String?,
        errorMessage: String,
        framework: Int = Framework.UNKNOWN,
    ) {
        RunAnywhereBridge.racAnalyticsEventEmitTtsSynthesis(
            EventType.TTS_SYNTHESIS_FAILED,
            synthesisId,
            modelId,
            modelName,
            0,
            0.0,
            0,
            0.0,
            0.0,
            0,
            framework,
            -5,
            errorMessage,
        )
    }

    // ========================================================================
    // VAD EVENTS
    // ========================================================================

    /**
     * Emit VAD started event via C++.
     */
    fun emitVadStarted() {
        RunAnywhereBridge.racAnalyticsEventEmitVad(
            EventType.VAD_STARTED,
            0.0,
            0f,
        )
    }

    /**
     * Emit VAD stopped event via C++.
     */
    fun emitVadStopped() {
        RunAnywhereBridge.racAnalyticsEventEmitVad(
            EventType.VAD_STOPPED,
            0.0,
            0f,
        )
    }

    /**
     * Emit VAD speech started event via C++.
     */
    fun emitVadSpeechStarted(energyLevel: Float = 0f) {
        RunAnywhereBridge.racAnalyticsEventEmitVad(
            EventType.VAD_SPEECH_STARTED,
            0.0,
            energyLevel,
        )
    }

    /**
     * Emit VAD speech ended event via C++.
     */
    fun emitVadSpeechEnded(speechDurationMs: Double, energyLevel: Float = 0f) {
        RunAnywhereBridge.racAnalyticsEventEmitVad(
            EventType.VAD_SPEECH_ENDED,
            speechDurationMs,
            energyLevel,
        )
    }

    /**
     * Emit VAD paused event via C++.
     */
    fun emitVadPaused() {
        RunAnywhereBridge.racAnalyticsEventEmitVad(
            EventType.VAD_PAUSED,
            0.0,
            0f,
        )
    }

    /**
     * Emit VAD resumed event via C++.
     */
    fun emitVadResumed() {
        RunAnywhereBridge.racAnalyticsEventEmitVad(
            EventType.VAD_RESUMED,
            0.0,
            0f,
        )
    }
}
