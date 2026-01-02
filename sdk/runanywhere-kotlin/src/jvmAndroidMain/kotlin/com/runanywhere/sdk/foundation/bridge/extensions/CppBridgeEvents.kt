/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Events extension for CppBridge.
 * Provides analytics event callback registration for C++ core.
 *
 * Follows iOS CppBridge+Telemetry.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

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
     * Event type constants matching C++ RAC_ANALYTICS_EVENT_* values.
     */
    object EventType {
        /** SDK initialization completed */
        const val SDK_INITIALIZED = 0

        /** SDK shutdown initiated */
        const val SDK_SHUTDOWN = 1

        /** Model loading started */
        const val MODEL_LOAD_STARTED = 10

        /** Model loading completed successfully */
        const val MODEL_LOAD_COMPLETED = 11

        /** Model loading failed */
        const val MODEL_LOAD_FAILED = 12

        /** Model unloaded */
        const val MODEL_UNLOADED = 13

        /** Inference started */
        const val INFERENCE_STARTED = 20

        /** Inference completed successfully */
        const val INFERENCE_COMPLETED = 21

        /** Inference failed */
        const val INFERENCE_FAILED = 22

        /** Inference cancelled */
        const val INFERENCE_CANCELLED = 23

        /** Download started */
        const val DOWNLOAD_STARTED = 30

        /** Download progress update */
        const val DOWNLOAD_PROGRESS = 31

        /** Download completed successfully */
        const val DOWNLOAD_COMPLETED = 32

        /** Download failed */
        const val DOWNLOAD_FAILED = 33

        /** Download cancelled */
        const val DOWNLOAD_CANCELLED = 34

        /** Error occurred */
        const val ERROR = 100

        /** Warning occurred */
        const val WARNING = 101

        /**
         * Get a human-readable name for the event type.
         */
        fun getName(type: Int): String = when (type) {
            SDK_INITIALIZED -> "SDK_INITIALIZED"
            SDK_SHUTDOWN -> "SDK_SHUTDOWN"
            MODEL_LOAD_STARTED -> "MODEL_LOAD_STARTED"
            MODEL_LOAD_COMPLETED -> "MODEL_LOAD_COMPLETED"
            MODEL_LOAD_FAILED -> "MODEL_LOAD_FAILED"
            MODEL_UNLOADED -> "MODEL_UNLOADED"
            INFERENCE_STARTED -> "INFERENCE_STARTED"
            INFERENCE_COMPLETED -> "INFERENCE_COMPLETED"
            INFERENCE_FAILED -> "INFERENCE_FAILED"
            INFERENCE_CANCELLED -> "INFERENCE_CANCELLED"
            DOWNLOAD_STARTED -> "DOWNLOAD_STARTED"
            DOWNLOAD_PROGRESS -> "DOWNLOAD_PROGRESS"
            DOWNLOAD_COMPLETED -> "DOWNLOAD_COMPLETED"
            DOWNLOAD_FAILED -> "DOWNLOAD_FAILED"
            DOWNLOAD_CANCELLED -> "DOWNLOAD_CANCELLED"
            ERROR -> "ERROR"
            WARNING -> "WARNING"
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
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Register the event callback with C++ via JNI
            // The callback will be invoked by C++ when analytics events occur
            // TODO: Call native registration
            // nativeSetEventCallback()

            isRegistered = true
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
            "Event: ${EventType.getName(eventType)} - $eventName"
        )

        // Route to the registered listener
        try {
            eventListener?.onEvent(eventType, eventName, eventData, timestampMs)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Error in event listener: ${e.message}"
            )
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the analytics event callback with C++ core.
     *
     * This registers [eventCallback] with the C++ rac_analytics_events_set_callback function.
     *
     * C API: rac_analytics_events_set_callback(rac_analytics_event_callback_t callback)
     */
    @JvmStatic
    private external fun nativeSetEventCallback()

    /**
     * Native method to unset the analytics event callback.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_analytics_events_set_callback(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetEventCallback()

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the analytics event callback and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetEventCallback()

            eventListener = null
            isRegistered = false
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
     * @param errorData Optional JSON-encoded error data
     */
    fun trackError(errorMessage: String, errorData: String? = null) {
        trackEvent(EventType.ERROR, errorMessage, errorData)
    }

    /**
     * Track a warning event.
     *
     * @param warningMessage The warning message
     * @param warningData Optional JSON-encoded warning data
     */
    fun trackWarning(warningMessage: String, warningData: String? = null) {
        trackEvent(EventType.WARNING, warningMessage, warningData)
    }
}
