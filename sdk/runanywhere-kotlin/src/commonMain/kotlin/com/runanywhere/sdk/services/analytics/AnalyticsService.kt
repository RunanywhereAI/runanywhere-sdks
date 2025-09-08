package com.runanywhere.sdk.services.analytics

import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.sync.SyncCoordinator
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.events.ComponentEvent
import com.runanywhere.sdk.events.ComponentInitializationEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.serialization.Serializable

/**
 * Analytics Service for SDK events tracking
 * Matches iOS AnalyticsService functionality with centralized telemetry
 */
class AnalyticsService(
    private val telemetryRepository: TelemetryRepository?,
    private val syncCoordinator: SyncCoordinator?
) {
    private val logger = SDKLogger("AnalyticsService")
    private val analyticsScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private var isInitialized = false

    suspend fun initialize() {
        if (isInitialized) return

        logger.info("Initializing AnalyticsService")

        // Subscribe to all SDK events for automatic tracking
        subscribeToSDKEvents()

        isInitialized = true
        logger.info("AnalyticsService initialized successfully")
    }

    /**
     * Subscribe to all SDK events for automatic analytics tracking
     */
    private fun subscribeToSDKEvents() {
        // Track initialization events
        EventBus.initializationEvents
            .onEach { event ->
                when (event) {
                    is SDKInitializationEvent.Started -> trackEvent(
                        AnalyticsEvent.SDKInitializationStarted()
                    )
                    is SDKInitializationEvent.Completed -> trackEvent(
                        AnalyticsEvent.SDKInitializationCompleted()
                    )
                    is SDKInitializationEvent.Failed -> trackEvent(
                        AnalyticsEvent.SDKInitializationFailed(event.error.message ?: "Unknown error")
                    )
                    is SDKInitializationEvent.StepStarted -> {
                        // Track step started events
                    }
                    is SDKInitializationEvent.StepCompleted -> {
                        // Track step completed events
                    }
                    is SDKInitializationEvent.StepFailed -> {
                        // Track step failed events
                    }
                }
            }
            .launchIn(analyticsScope)

        // Track component events
        EventBus.componentEvents
            .onEach { event ->
                when (event) {
                    is ComponentInitializationEvent.ComponentReady -> trackEvent(
                        AnalyticsEvent.ComponentInitialized(event.component.name)
                    )
                    is ComponentInitializationEvent.ComponentFailed -> trackEvent(
                        AnalyticsEvent.ComponentInitializationFailed(
                            event.component.name,
                            event.error.message ?: "Unknown error"
                        )
                    )
                    else -> { /* Track other component events as needed */ }
                }
            }
            .launchIn(analyticsScope)

        // Track model events
        EventBus.modelEvents
            .onEach { event ->
                trackModelEvent(event)
            }
            .launchIn(analyticsScope)

        // Track voice events
        EventBus.voiceEvents
            .onEach { event ->
                trackVoiceEvent(event)
            }
            .launchIn(analyticsScope)
    }

    /**
     * Track a custom analytics event
     */
    suspend fun trackEvent(event: AnalyticsEvent) {
        if (!isInitialized) {
            logger.warn("AnalyticsService not initialized, queuing event: ${event.eventType}")
            return
        }

        try {
            val telemetryData = TelemetryData(
                type = mapEventTypeToTelemetryType(event.eventType),
                name = event.eventType,
                properties = event.eventData.mapValues { it.value.toString() },
                sessionId = getCurrentSessionId(),
                deviceId = getDeviceId(),
                sdkVersion = "0.1.0",
                osVersion = getOSVersion()
            )

            // Store telemetry data
            telemetryRepository?.saveEvent(telemetryData)

            // Sync to backend if available (async operation)
            // Note: Actual sync implementation would go here

            logger.debug("Tracked event: ${event.eventType}")

        } catch (e: Exception) {
            logger.error("Failed to track event: ${event.eventType}", e)
        }
    }

    /**
     * Track SDK initialization metrics
     */
    suspend fun trackInitializationMetrics(
        stepName: String,
        duration: Long,
        success: Boolean,
        errorMessage: String? = null
    ) {
        val event = AnalyticsEvent.InitializationStep(
            step = stepName,
            duration = duration,
            success = success,
            errorMessage = errorMessage
        )
        trackEvent(event)
    }

    /**
     * Track component usage
     */
    suspend fun trackComponentUsage(
        componentName: String,
        action: String,
        duration: Long? = null,
        success: Boolean = true,
        metadata: Map<String, Any>? = null
    ) {
        val event = AnalyticsEvent.ComponentUsage(
            component = componentName,
            action = action,
            duration = duration,
            success = success,
            metadata = metadata ?: emptyMap()
        )
        trackEvent(event)
    }

    /**
     * Track performance metrics
     */
    suspend fun trackPerformanceMetrics(
        operation: String,
        duration: Long,
        memoryUsage: Long? = null,
        cpuUsage: Float? = null,
        success: Boolean = true
    ) {
        val event = AnalyticsEvent.Performance(
            operation = operation,
            duration = duration,
            memoryUsage = memoryUsage,
            cpuUsage = cpuUsage,
            success = success
        )
        trackEvent(event)
    }

    private fun trackModelEvent(event: com.runanywhere.sdk.events.SDKModelEvent) {
        analyticsScope.launch {
            val analyticsEvent = when (event) {
                is com.runanywhere.sdk.events.SDKModelEvent.LoadStarted ->
                    AnalyticsEvent.ModelOperation("load_started", event.modelId)
                is com.runanywhere.sdk.events.SDKModelEvent.LoadCompleted ->
                    AnalyticsEvent.ModelOperation("load_completed", event.modelId)
                is com.runanywhere.sdk.events.SDKModelEvent.LoadFailed ->
                    AnalyticsEvent.ModelOperation("load_failed", event.modelId, event.error.message)
                is com.runanywhere.sdk.events.SDKModelEvent.DownloadStarted ->
                    AnalyticsEvent.ModelOperation("download_started", event.modelId)
                is com.runanywhere.sdk.events.SDKModelEvent.DownloadCompleted ->
                    AnalyticsEvent.ModelOperation("download_completed", event.modelId)
                is com.runanywhere.sdk.events.SDKModelEvent.DownloadFailed ->
                    AnalyticsEvent.ModelOperation("download_failed", event.modelId, event.error.message)
                else -> return@launch
            }
            trackEvent(analyticsEvent)
        }
    }

    private fun trackVoiceEvent(event: com.runanywhere.sdk.events.SDKVoiceEvent) {
        analyticsScope.launch {
            val analyticsEvent = when (event) {
                is com.runanywhere.sdk.events.SDKVoiceEvent.TranscriptionStarted ->
                    AnalyticsEvent.VoiceOperation("transcription_started")
                is com.runanywhere.sdk.events.SDKVoiceEvent.TranscriptionFinal ->
                    AnalyticsEvent.VoiceOperation("transcription_completed", mapOf("text_length" to event.text.length))
                is com.runanywhere.sdk.events.SDKVoiceEvent.PipelineError ->
                    AnalyticsEvent.VoiceOperation("pipeline_error", mapOf("error" to (event.error.message ?: "Unknown")))
                else -> return@launch
            }
            trackEvent(analyticsEvent)
        }
    }

    /**
     * Get analytics statistics
     */
    suspend fun getAnalyticsStats(): AnalyticsStats {
        val allTelemetry = telemetryRepository?.getAllEvents() ?: emptyList()

        return AnalyticsStats(
            totalEvents = allTelemetry.size,
            eventsByType = allTelemetry.groupBy { it.type.name }.mapValues { it.value.size },
            lastEventTime = allTelemetry.maxByOrNull { it.timestamp }?.timestamp ?: 0,
            sessionCount = allTelemetry.map { it.sessionId }.toSet().size
        )
    }

    /**
     * Flush all pending analytics to backend
     */
    suspend fun flush() {
        // TODO: Implement telemetry sync mechanism when available
    }

    suspend fun cleanup() {
        logger.info("Cleaning up AnalyticsService")
        flush()
        isInitialized = false
    }

    // Helper methods
    private fun getCurrentSessionId(): String = "session-${System.currentTimeMillis()}"
    private fun getCurrentUserId(): String? = null // Will be set after authentication
    private fun getDeviceId(): String = "device-id" // Will be provided by DeviceInfoService
}

/**
 * Analytics event definitions matching iOS patterns
 */
sealed class AnalyticsEvent(
    val eventType: String,
    val eventData: Map<String, Any>
) {
    class SDKInitializationStarted : AnalyticsEvent(
        "sdk_initialization_started",
        mapOf("timestamp" to System.currentTimeMillis())
    )

    class SDKInitializationCompleted : AnalyticsEvent(
        "sdk_initialization_completed",
        mapOf("timestamp" to System.currentTimeMillis())
    )

    class SDKInitializationFailed(error: String) : AnalyticsEvent(
        "sdk_initialization_failed",
        mapOf("error" to error, "timestamp" to System.currentTimeMillis())
    )

    class ComponentInitialized(component: String) : AnalyticsEvent(
        "component_initialized",
        mapOf("component" to component, "timestamp" to System.currentTimeMillis())
    )

    class ComponentInitializationFailed(component: String, error: String) : AnalyticsEvent(
        "component_initialization_failed",
        mapOf("component" to component, "error" to error, "timestamp" to System.currentTimeMillis())
    )

    class InitializationStep(
        step: String,
        duration: Long,
        success: Boolean,
        errorMessage: String? = null
    ) : AnalyticsEvent(
        "initialization_step",
        mapOf(
            "step" to step,
            "duration" to duration,
            "success" to success,
            "timestamp" to System.currentTimeMillis()
        ) + if (errorMessage != null) mapOf("error" to errorMessage) else emptyMap()
    )

    class ComponentUsage(
        component: String,
        action: String,
        duration: Long?,
        success: Boolean,
        metadata: Map<String, Any>
    ) : AnalyticsEvent(
        "component_usage",
        mapOf(
            "component" to component,
            "action" to action,
            "success" to success,
            "timestamp" to System.currentTimeMillis()
        ) + (if (duration != null) mapOf("duration" to duration) else emptyMap()) + metadata
    )

    class Performance(
        operation: String,
        duration: Long,
        memoryUsage: Long?,
        cpuUsage: Float?,
        success: Boolean
    ) : AnalyticsEvent(
        "performance_metrics",
        mapOf(
            "operation" to operation,
            "duration" to duration,
            "success" to success,
            "timestamp" to System.currentTimeMillis()
        ) + (if (memoryUsage != null) mapOf("memory_usage" to memoryUsage) else emptyMap()) +
          (if (cpuUsage != null) mapOf("cpu_usage" to cpuUsage) else emptyMap())
    )

    class ModelOperation(
        operation: String,
        modelId: String,
        error: String? = null
    ) : AnalyticsEvent(
        "model_operation",
        mapOf(
            "operation" to operation,
            "model_id" to modelId,
            "timestamp" to System.currentTimeMillis()
        ) + (if (error != null) mapOf("error" to error) else emptyMap())
    )

    class VoiceOperation(
        operation: String,
        metadata: Map<String, Any> = emptyMap()
    ) : AnalyticsEvent(
        "voice_operation",
        mapOf(
            "operation" to operation,
            "timestamp" to System.currentTimeMillis()
        ) + metadata
    )
}

/**
 * Analytics statistics data
 */
@Serializable
data class AnalyticsStats(
    val totalEvents: Int,
    val eventsByType: Map<String, Int>,
    val lastEventTime: Long,
    val sessionCount: Int
)

/**
 * Helper functions for Analytics Service
 */
private fun mapEventTypeToTelemetryType(eventType: String): com.runanywhere.sdk.data.models.TelemetryEventType {
    return when (eventType) {
        "sdk_initialization_started", "sdk_initialization_completed", "sdk_initialization_failed" ->
            com.runanywhere.sdk.data.models.TelemetryEventType.SDK_INITIALIZATION
        "component_initialized", "component_initialization_failed" ->
            com.runanywhere.sdk.data.models.TelemetryEventType.SDK_INITIALIZATION
        "model_operation" ->
            com.runanywhere.sdk.data.models.TelemetryEventType.MODEL_LOAD_STARTED
        "voice_operation" ->
            com.runanywhere.sdk.data.models.TelemetryEventType.STT_INITIALIZATION
        else ->
            com.runanywhere.sdk.data.models.TelemetryEventType.SDK_INITIALIZATION
    }
}

private fun getOSVersion(): String {
    // Platform-specific implementation will be provided by expect/actual
    return "Unknown"
}
