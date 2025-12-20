package com.runanywhere.sdk.infrastructure.analytics

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.network.models.DevAnalyticsSubmissionRequest
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.sync.SyncCoordinator
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.constants.BuildToken
import com.runanywhere.sdk.foundation.currentTimeISO8601
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.foundation.supabase.SupabaseClient
import com.runanywhere.sdk.foundation.supabase.SupabaseConfig
import com.runanywhere.sdk.infrastructure.events.ComponentInitializationEvent
import com.runanywhere.sdk.infrastructure.events.EventBus
import com.runanywhere.sdk.infrastructure.events.SDKInitializationEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable

/**
 * Analytics Service for SDK events tracking
 * Matches iOS AnalyticsService functionality with centralized telemetry
 *
 * Reference: iOS RunAnywhere.swift submitGenerationAnalytics()
 */
class AnalyticsService internal constructor(
    private val telemetryRepository: TelemetryRepository?,
    @Suppress("unused") private val syncCoordinator: SyncCoordinator?,
    private val supabaseConfig: SupabaseConfig? = null,
    private val environment: SDKEnvironment = SDKEnvironment.PRODUCTION,
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
                    is SDKInitializationEvent.Started ->
                        trackEvent(
                            SDKAnalyticsEvent.SDKInitializationStarted(),
                        )
                    is SDKInitializationEvent.Completed ->
                        trackEvent(
                            SDKAnalyticsEvent.SDKInitializationCompleted(),
                        )
                    is SDKInitializationEvent.Failed ->
                        trackEvent(
                            SDKAnalyticsEvent.SDKInitializationFailed(event.error.message ?: "Unknown error"),
                        )
                    is SDKInitializationEvent.ConfigurationLoaded ->
                        trackEvent(
                            SDKAnalyticsEvent.SDKConfigurationLoaded(event.source),
                        )
                    is SDKInitializationEvent.ServicesBootstrapped ->
                        trackEvent(
                            SDKAnalyticsEvent.SDKServicesBootstrapped(),
                        )
                    is SDKInitializationEvent.StepStarted -> {
                        // Optional: track step events if needed
                    }
                    is SDKInitializationEvent.StepCompleted -> {
                        // Optional: track step completion if needed
                    }
                }
            }.launchIn(analyticsScope)

        // Track component events
        EventBus.componentEvents
            .onEach { event ->
                when (event) {
                    is ComponentInitializationEvent.ComponentReady ->
                        trackEvent(
                            SDKAnalyticsEvent.ComponentInitialized(event.component),
                        )
                    is ComponentInitializationEvent.ComponentFailed ->
                        trackEvent(
                            SDKAnalyticsEvent.ComponentInitializationFailed(
                                event.component,
                                event.error.message ?: "Unknown error",
                            ),
                        )
                    else -> { /* Track other component events as needed */ }
                }
            }.launchIn(analyticsScope)

        // Track model events
        EventBus.modelEvents
            .onEach { event ->
                trackModelEvent(event)
            }.launchIn(analyticsScope)

        // Track voice events
        EventBus.voiceEvents
            .onEach { event ->
                trackVoiceEvent(event)
            }.launchIn(analyticsScope)
    }

    /**
     * Track a custom analytics event
     */
    suspend fun trackEvent(event: SDKAnalyticsEvent) {
        if (!isInitialized) {
            logger.warn("AnalyticsService not initialized, queuing event: ${event.eventType}")
            return
        }

        try {
            val telemetryData =
                TelemetryData(
                    type = mapEventTypeToTelemetryType(event.eventType),
                    name = event.eventType,
                    properties = event.eventData.mapValues { it.value.toString() },
                    sessionId = getCurrentSessionId(),
                    deviceId = getDeviceId(),
                    sdkVersion = "0.1.0",
                    osVersion = getOSVersion(),
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
        errorMessage: String? = null,
    ) {
        val event =
            SDKAnalyticsEvent.InitializationStep(
                step = stepName,
                duration = duration,
                success = success,
                errorMessage = errorMessage,
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
        metadata: Map<String, Any>? = null,
    ) {
        val event =
            SDKAnalyticsEvent.ComponentUsage(
                component = componentName,
                action = action,
                duration = duration,
                success = success,
                metadata = metadata ?: emptyMap(),
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
        success: Boolean = true,
    ) {
        val event =
            SDKAnalyticsEvent.Performance(
                operation = operation,
                duration = duration,
                memoryUsage = memoryUsage,
                cpuUsage = cpuUsage,
                success = success,
            )
        trackEvent(event)
    }

    private fun trackModelEvent(event: com.runanywhere.sdk.infrastructure.events.SDKModelEvent) {
        analyticsScope.launch {
            val analyticsEvent =
                when (event) {
                    is com.runanywhere.sdk.infrastructure.events.SDKModelEvent.LoadStarted ->
                        SDKAnalyticsEvent.ModelOperation("load_started", event.modelId)
                    is com.runanywhere.sdk.infrastructure.events.SDKModelEvent.LoadCompleted ->
                        SDKAnalyticsEvent.ModelOperation("load_completed", event.modelId)
                    is com.runanywhere.sdk.infrastructure.events.SDKModelEvent.LoadFailed ->
                        SDKAnalyticsEvent.ModelOperation("load_failed", event.modelId, event.error.message)
                    is com.runanywhere.sdk.infrastructure.events.SDKModelEvent.DownloadStarted ->
                        SDKAnalyticsEvent.ModelOperation("download_started", event.modelId)
                    is com.runanywhere.sdk.infrastructure.events.SDKModelEvent.DownloadCompleted ->
                        SDKAnalyticsEvent.ModelOperation("download_completed", event.modelId)
                    is com.runanywhere.sdk.infrastructure.events.SDKModelEvent.DownloadFailed ->
                        SDKAnalyticsEvent.ModelOperation("download_failed", event.modelId, event.error.message)
                    else -> return@launch
                }
            trackEvent(analyticsEvent)
        }
    }

    private fun trackVoiceEvent(event: com.runanywhere.sdk.infrastructure.events.SDKVoiceEvent) {
        analyticsScope.launch {
            val analyticsEvent =
                when (event) {
                    is com.runanywhere.sdk.infrastructure.events.SDKVoiceEvent.TranscriptionStarted ->
                        SDKAnalyticsEvent.VoiceOperation("transcription_started")
                    is com.runanywhere.sdk.infrastructure.events.SDKVoiceEvent.TranscriptionFinal ->
                        SDKAnalyticsEvent.VoiceOperation("transcription_completed", mapOf("text_length" to event.text.length))
                    is com.runanywhere.sdk.infrastructure.events.SDKVoiceEvent.PipelineError ->
                        SDKAnalyticsEvent.VoiceOperation("pipeline_error", mapOf("error" to (event.error.message ?: "Unknown")))
                    else -> return@launch
                }
            trackEvent(analyticsEvent)
        }
    }

    /**
     * Submit generation analytics to Supabase (development mode)
     * Matches iOS RunAnywhere.submitGenerationAnalytics()
     *
     * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift:630
     */
    suspend fun submitGenerationAnalytics(
        generationId: String,
        modelId: String,
        performanceMetrics: PerformanceMetrics,
        inputTokens: Int,
        outputTokens: Int,
        success: Boolean,
        executionTarget: String,
    ) {
        // Only submit in development mode
        if (environment != SDKEnvironment.DEVELOPMENT) {
            logger.info("📊 [ANALYTICS] Skipping analytics submission (environment=${environment.name}, not DEVELOPMENT)")
            return
        }

        logger.info("📊 [ANALYTICS] ========== Starting Analytics Submission ==========")
        logger.info("📊 [ANALYTICS] Environment: ${environment.name}")
        logger.info("📊 [ANALYTICS] Generation ID: $generationId")
        logger.info("📊 [ANALYTICS] Model ID: $modelId")

        // Non-blocking background submission
        analyticsScope.launch(Dispatchers.IO) {
            try {
                // Get device ID dynamically from ServiceContainer
                val currentDeviceId = com.runanywhere.sdk.foundation.ServiceContainer.shared.deviceId
                logger.info("📊 [ANALYTICS] Device ID: $currentDeviceId")

                // Capture host app information
                val hostAppInfo =
                    com.runanywhere.sdk.foundation
                        .getHostAppInfo()
                logger.info("📊 [ANALYTICS] Host App: ${hostAppInfo.name} (${hostAppInfo.identifier}) v${hostAppInfo.version}")

                val request =
                    DevAnalyticsSubmissionRequest(
                        generationId = generationId,
                        deviceId = currentDeviceId,
                        modelId = modelId,
                        timeToFirstTokenMs = performanceMetrics.timeToFirstTokenMs,
                        tokensPerSecond = performanceMetrics.tokensPerSecond,
                        totalGenerationTimeMs = performanceMetrics.inferenceTimeMs.toDouble(),
                        inputTokens = inputTokens,
                        outputTokens = outputTokens,
                        success = success,
                        executionTarget = executionTarget,
                        buildToken = BuildToken.token,
                        sdkVersion = com.runanywhere.sdk.utils.SDKConstants.SDK_VERSION,
                        timestamp = currentTimeISO8601(), // ISO8601 format
                        hostAppIdentifier = hostAppInfo.identifier,
                        hostAppName = hostAppInfo.name,
                        hostAppVersion = hostAppInfo.version,
                    )

                logger.info("📊 [ANALYTICS] Analytics request prepared")
                logger.info("📊 [ANALYTICS] Supabase config available: ${supabaseConfig != null}")

                if (supabaseConfig != null) {
                    logger.info("📊 [ANALYTICS] Submitting to Supabase...")
                    submitAnalyticsViaSupabase(request, supabaseConfig)
                } else {
                    logger.warning("📊 [ANALYTICS] ❌ No Supabase config available for analytics submission")
                }
            } catch (e: Exception) {
                // Fail silently - analytics should never break the SDK
                logger.warning("📊 [ANALYTICS] ❌ Analytics submission failed (non-critical): ${e.message}")
            }
        }
    }

    /**
     * Submit analytics via Supabase REST API
     * Matches iOS submitAnalyticsViaSupabase()
     */
    private suspend fun submitAnalyticsViaSupabase(
        request: DevAnalyticsSubmissionRequest,
        config: SupabaseConfig,
    ) = withContext(Dispatchers.IO) {
        val supabaseClient = SupabaseClient(config)
        try {
            val result = supabaseClient.submitAnalytics(request)
            if (result.isSuccess) {
                logger.debug("📊 Analytics submitted successfully to Supabase")
            } else {
                logger.warning("⚠️ Analytics submission failed: ${result.exceptionOrNull()?.message}")
            }
        } finally {
            supabaseClient.close()
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
            sessionCount = allTelemetry.map { it.sessionId }.toSet().size,
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
    private fun getCurrentSessionId(): String = "session-${currentTimeMillis()}"

    @Suppress("FunctionOnlyReturningConstant") // TODO: Will be provided by DeviceInfoService
    private fun getDeviceId(): String = "device-id"
}

/**
 * Performance metrics for generation analytics
 * Matches iOS PerformanceMetrics struct
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/PerformanceMetrics.swift
 */
data class PerformanceMetrics(
    /** Time spent on tokenization (milliseconds) */
    val tokenizationTimeMs: Double = 0.0,
    /** Time spent on inference (milliseconds) */
    val inferenceTimeMs: Double = 0.0,
    /** Time spent on post-processing (milliseconds) */
    val postProcessingTimeMs: Double = 0.0,
    /** Tokens generated per second */
    val tokensPerSecond: Double = 0.0,
    /** Peak memory usage during generation */
    val peakMemoryUsage: Long = 0,
    /** Queue wait time if any (milliseconds) */
    val queueWaitTimeMs: Double = 0.0,
    /** Time to first token (milliseconds) - time from request start to first token */
    val timeToFirstTokenMs: Double? = null,
    /** Time spent in thinking mode (milliseconds) - only if model uses thinking */
    val thinkingTimeMs: Double? = null,
    /** Time spent generating response content after thinking (milliseconds) */
    val responseTimeMs: Double? = null,
    /** Timestamp when thinking started (relative to generation start, in milliseconds) */
    val thinkingStartTimeMs: Double? = null,
    /** Timestamp when thinking ended (relative to generation start, in milliseconds) */
    val thinkingEndTimeMs: Double? = null,
    /** Timestamp when first response token arrived (relative to generation start, in milliseconds) */
    val firstResponseTokenTimeMs: Double? = null,
)

/**
 * Analytics event definitions matching iOS patterns.
 * Named SDKAnalyticsEvent to avoid conflict with the AnalyticsEvent interface in AnalyticsQueueManager.
 */
sealed class SDKAnalyticsEvent(
    val eventType: String,
    val eventData: Map<String, Any>,
) {
    class SDKInitializationStarted :
        SDKAnalyticsEvent(
            "sdk_initialization_started",
            mapOf("timestamp" to currentTimeMillis()),
        )

    class SDKInitializationCompleted :
        SDKAnalyticsEvent(
            "sdk_initialization_completed",
            mapOf("timestamp" to currentTimeMillis()),
        )

    class SDKInitializationFailed(
        error: String,
    ) : SDKAnalyticsEvent(
            "sdk_initialization_failed",
            mapOf("error" to error, "timestamp" to currentTimeMillis()),
        )

    class SDKConfigurationLoaded(
        source: String,
    ) : SDKAnalyticsEvent(
            "sdk_configuration_loaded",
            mapOf("source" to source, "timestamp" to currentTimeMillis()),
        )

    class SDKServicesBootstrapped :
        SDKAnalyticsEvent(
            "sdk_services_bootstrapped",
            mapOf("timestamp" to currentTimeMillis()),
        )

    class ComponentInitialized(
        component: String,
    ) : SDKAnalyticsEvent(
            "component_initialized",
            mapOf("component" to component, "timestamp" to currentTimeMillis()),
        )

    class ComponentInitializationFailed(
        component: String,
        error: String,
    ) : SDKAnalyticsEvent(
            "component_initialization_failed",
            mapOf("component" to component, "error" to error, "timestamp" to currentTimeMillis()),
        )

    class InitializationStep(
        step: String,
        duration: Long,
        success: Boolean,
        errorMessage: String? = null,
    ) : SDKAnalyticsEvent(
            "initialization_step",
            mapOf(
                "step" to step,
                "duration" to duration,
                "success" to success,
                "timestamp" to currentTimeMillis(),
            ) + if (errorMessage != null) mapOf("error" to errorMessage) else emptyMap(),
        )

    class ComponentUsage(
        component: String,
        action: String,
        duration: Long?,
        success: Boolean,
        metadata: Map<String, Any>,
    ) : SDKAnalyticsEvent(
            "component_usage",
            mapOf(
                "component" to component,
                "action" to action,
                "success" to success,
                "timestamp" to currentTimeMillis(),
            ) + (if (duration != null) mapOf("duration" to duration) else emptyMap()) + metadata,
        )

    class Performance(
        operation: String,
        duration: Long,
        memoryUsage: Long?,
        cpuUsage: Float?,
        success: Boolean,
    ) : SDKAnalyticsEvent(
            "performance_metrics",
            mapOf(
                "operation" to operation,
                "duration" to duration,
                "success" to success,
                "timestamp" to currentTimeMillis(),
            ) + (if (memoryUsage != null) mapOf("memory_usage" to memoryUsage) else emptyMap()) +
                (if (cpuUsage != null) mapOf("cpu_usage" to cpuUsage) else emptyMap()),
        )

    class ModelOperation(
        operation: String,
        modelId: String,
        error: String? = null,
    ) : SDKAnalyticsEvent(
            "model_operation",
            mapOf(
                "operation" to operation,
                "model_id" to modelId,
                "timestamp" to currentTimeMillis(),
            ) + (if (error != null) mapOf("error" to error) else emptyMap()),
        )

    class VoiceOperation(
        operation: String,
        metadata: Map<String, Any> = emptyMap(),
    ) : SDKAnalyticsEvent(
            "voice_operation",
            mapOf(
                "operation" to operation,
                "timestamp" to currentTimeMillis(),
            ) + metadata,
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
    val sessionCount: Int,
)

/**
 * Helper functions for Analytics Service
 */
private fun mapEventTypeToTelemetryType(eventType: String): com.runanywhere.sdk.data.models.TelemetryEventType =
    when (eventType) {
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

@Suppress("FunctionOnlyReturningConstant") // TODO: Platform-specific implementation will be provided by expect/actual
private fun getOSVersion(): String = "Unknown"
