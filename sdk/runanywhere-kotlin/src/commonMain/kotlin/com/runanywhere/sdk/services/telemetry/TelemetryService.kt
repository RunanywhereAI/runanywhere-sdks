package com.runanywhere.sdk.services.telemetry

import com.runanywhere.sdk.data.models.ErrorTelemetryData
import com.runanywhere.sdk.data.models.PerformanceTelemetryData
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.models.STTTelemetryData
import com.runanywhere.sdk.data.models.SessionTelemetryData
import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventType
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.models.TelemetryEventData
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.sync.SyncCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.datetime.Clock
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.runanywhere.sdk.data.models.generateUUID

/**
 * Telemetry Service
 * One-to-one translation from iOS Swift Actor to Kotlin with thread-safety
 * Handles analytics, performance tracking, and error reporting
 */
class TelemetryService(
    private val telemetryRepository: TelemetryRepository,
    private val syncCoordinator: SyncCoordinator?
) {

    private val logger = SDKLogger("TelemetryService")
    private val mutex = Mutex()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Session management
    private val sessionId = generateUUID()
    private var currentSession: SessionTelemetryData? = null

    // Batching configuration
    private val batchSize = 10
    private val batchTimeoutMs = 30_000L // 30 seconds
    private var pendingEvents = mutableListOf<TelemetryData>()
    private var lastBatchSent = Clock.System.now().toEpochMilliseconds()

    // Device and app information
    private var deviceId: String? = null
    private var appVersion: String? = null
    private var sdkVersion: String = "1.0.0"

    init {
        // Start periodic batch sending
        scope.launch {
            while (true) {
                delay(batchTimeoutMs)
                sendPendingBatches()
            }
        }
    }

    /**
     * Track a telemetry event data
     * Simple event tracking for components
     */
    suspend fun trackEvent(event: TelemetryEventData) = mutex.withLock {
        logger.debug("Tracking event data: ${event.type}")

        try {
            telemetryRepository.saveEventData(event)
            logger.debug("Event data tracked: ${event.type}")
        } catch (e: Exception) {
            logger.error("Failed to track event data: ${event.type} - ${e.message}")
        }
    }

    /**
     * Track a telemetry event
     * Equivalent to iOS: func trackEvent(_ type: TelemetryEventType, properties: [String: String]) async throws
     */
    suspend fun trackEvent(type: TelemetryEventType, properties: Map<String, String> = emptyMap()) = mutex.withLock {
        logger.debug("Tracking event: $type")

        try {
            val event = TelemetryData(
                type = type,
                name = type.name.lowercase().replace('_', '.'),
                properties = properties,
                sessionId = sessionId,
                deviceId = deviceId ?: "unknown",
                appVersion = appVersion,
                sdkVersion = sdkVersion,
                osVersion = "Android"
            )

            // Save to repository
            telemetryRepository.saveEvent(event)

            // Add to pending batch
            pendingEvents.add(event)

            // Send batch if full
            if (pendingEvents.size >= batchSize) {
                sendBatch()
            }

            logger.debug("Event tracked: $type")

        } catch (e: Exception) {
            logger.error("Failed to track event: $type - ${e.message}")
            // Don't throw - telemetry failures shouldn't break the app
        }
    }

    /**
     * Track a custom event
     * Equivalent to iOS: func trackCustomEvent(_ name: String, properties: [String: String]) async throws
     */
    suspend fun trackCustomEvent(name: String, properties: Map<String, String> = emptyMap()) = mutex.withLock {
        logger.debug("Tracking custom event: $name")

        try {
            val event = TelemetryData(
                type = TelemetryEventType.CUSTOM_EVENT,
                name = name,
                properties = properties,
                sessionId = sessionId,
                deviceId = deviceId ?: "unknown",
                appVersion = appVersion,
                sdkVersion = sdkVersion,
                osVersion = "Android"
            )

            telemetryRepository.saveEvent(event)
            pendingEvents.add(event)

            if (pendingEvents.size >= batchSize) {
                sendBatch()
            }

            logger.debug("Custom event tracked: $name")

        } catch (e: Exception) {
            logger.error("Failed to track custom event: $name - ${e.message}")
        }
    }

    /**
     * Get all events
     * Equivalent to iOS: func getAllEvents() async throws -> [TelemetryData]
     */
    suspend fun getAllEvents(): List<TelemetryData> = mutex.withLock {
        logger.debug("Getting all events")

        return try {
            telemetryRepository.getAllEvents()
        } catch (e: Exception) {
            logger.error("Failed to get all events: ${e.message}")
            throw SDKError.RuntimeError("Failed to get all events: ${e.message}")
        }
    }

    /**
     * Mark events as sent
     * Equivalent to iOS: func markEventsSent(_ eventIds: [String]) async throws
     */
    suspend fun markEventsSent(eventIds: List<String>) = mutex.withLock {
        logger.debug("Marking ${eventIds.size} events as sent")

        try {
            telemetryRepository.markEventsSent(eventIds, Clock.System.now().toEpochMilliseconds())
            logger.info("${eventIds.size} events marked as sent")

        } catch (e: Exception) {
            logger.error("Failed to mark events as sent: ${e.message}")
            throw SDKError.RuntimeError("Failed to mark events as sent: ${e.message}")
        }
    }

    /**
     * Sync telemetry to remote
     * Equivalent to iOS: func syncTelemetry() async throws
     */
    suspend fun syncTelemetry() = mutex.withLock {
        logger.debug("Syncing telemetry")

        try {
            // Send pending batches first
            sendBatch()

            // Use sync coordinator if available
            syncCoordinator?.let { coordinator ->
                coordinator.syncTelemetry()
            } ?: run {
                // Direct sync without coordinator
                val unsentEvents = telemetryRepository.getUnsentEvents()
                if (unsentEvents.isNotEmpty()) {
                    val batch = TelemetryBatch(
                        events = unsentEvents,
                        deviceId = deviceId ?: "unknown",
                        sessionId = sessionId,
                        appVersion = appVersion,
                        sdkVersion = sdkVersion
                    )

                    telemetryRepository.sendBatch(batch)
                    markEventsSent(unsentEvents.map { it.id })
                }
            }

            logger.info("Telemetry synced successfully")

        } catch (e: Exception) {
            logger.error("Failed to sync telemetry: ${e.message}")
            throw SDKError.NetworkError("Failed to sync telemetry: ${e.message}")
        }
    }

    // STT-specific analytics helpers (equivalent to iOS helpers)

    /**
     * Track STT initialization
     * Equivalent to iOS STT analytics helper
     */
    suspend fun trackSTTInitialization(modelId: String, success: Boolean, loadTime: Long? = null) {
        val properties = mutableMapOf<String, String>()
        properties["model_id"] = modelId
        properties["success"] = success.toString()
        loadTime?.let { properties["load_time_ms"] = it.toString() }

        trackEvent(TelemetryEventType.STT_INITIALIZATION, properties)
    }

    /**
     * Track STT model loading
     * Equivalent to iOS STT analytics helper
     */
    suspend fun trackSTTModelLoad(modelId: String, success: Boolean, loadTime: Long, modelSizeMB: Long) {
        val properties = mutableMapOf<String, String>()
        properties["model_id"] = modelId
        properties["success"] = success.toString()
        properties["load_time_ms"] = loadTime.toString()
        properties["model_size_mb"] = modelSizeMB.toString()

        trackEvent(TelemetryEventType.STT_MODEL_LOADED, properties)
    }

    /**
     * Track STT transcription with detailed metrics
     * Enhanced version with STT-specific data
     */
    suspend fun trackSTTTranscription(
        modelId: String,
        success: Boolean,
        processingTime: Long,
        audioDuration: Long? = null,
        wordCount: Int? = null,
        confidence: Float? = null,
        language: String? = null
    ) {
        val properties = mutableMapOf<String, String>()
        properties["model_id"] = modelId
        properties["success"] = success.toString()
        properties["processing_time_ms"] = processingTime.toString()
        audioDuration?.let { properties["audio_duration_ms"] = it.toString() }
        wordCount?.let { properties["word_count"] = it.toString() }
        confidence?.let { properties["confidence"] = it.toString() }
        language?.let { properties["language"] = it }

        trackEvent(TelemetryEventType.STT_TRANSCRIPTION_COMPLETED, properties)
    }

    /**
     * Track VAD detection
     * STT-specific analytics for voice activity detection
     */
    suspend fun trackVADDetection(detected: Boolean, confidence: Float? = null) {
        val properties = mutableMapOf<String, String>()
        properties["detected"] = detected.toString()
        confidence?.let { properties["confidence"] = it.toString() }

        trackEvent(TelemetryEventType.STT_VAD_DETECTED, properties)
    }

    // General analytics helpers

    /**
     * Track initialization
     * Equivalent to iOS analytics helper
     */
    suspend fun trackInitialization(apiKey: String, version: String) {
        val properties = mapOf(
            "api_key_hash" to apiKey.hashCode().toString(),
            "version" to version,
            "platform" to "android"
        )

        trackEvent(TelemetryEventType.SDK_INITIALIZATION, properties)
    }

    /**
     * Track model load
     * Equivalent to iOS analytics helper
     */
    suspend fun trackModelLoad(modelId: String, success: Boolean, loadTime: Long) {
        val properties = mapOf(
            "model_id" to modelId,
            "success" to success.toString(),
            "load_time_ms" to loadTime.toString()
        )

        trackEvent(TelemetryEventType.MODEL_LOAD_COMPLETED, properties)
    }

    /**
     * Track generation
     * Equivalent to iOS analytics helper
     */
    suspend fun trackGeneration(
        modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        duration: Long
    ) {
        val properties = mapOf(
            "model_id" to modelId,
            "input_tokens" to inputTokens.toString(),
            "output_tokens" to outputTokens.toString(),
            "duration_ms" to duration.toString(),
            "tokens_per_second" to (outputTokens.toFloat() / (duration / 1000f)).toString()
        )

        trackEvent(TelemetryEventType.GENERATION_COMPLETED, properties)
    }

    /**
     * Track error with context
     * Equivalent to iOS analytics helper
     */
    suspend fun trackError(
        error: Throwable,
        context: String,
        additionalInfo: Map<String, String> = emptyMap()
    ) {
        val properties = mutableMapOf<String, String>()
        properties["error_type"] = error::class.java.simpleName
        properties["error_message"] = error.message ?: "Unknown error"
        properties["context"] = context
        properties.putAll(additionalInfo)

        trackEvent(TelemetryEventType.SDK_ERROR, properties)
    }

    /**
     * Track performance metrics
     * For system performance monitoring
     */
    suspend fun trackPerformance(
        operation: String,
        duration: Long,
        memoryUsageMB: Long? = null,
        cpuUsage: Float? = null
    ) {
        val properties = mutableMapOf<String, String>()
        properties["operation"] = operation
        properties["duration_ms"] = duration.toString()
        memoryUsageMB?.let { properties["memory_usage_mb"] = it.toString() }
        cpuUsage?.let { properties["cpu_usage_percent"] = it.toString() }

        trackEvent(TelemetryEventType.PERFORMANCE_BENCHMARK, properties)
    }

    /**
     * Initialize telemetry service
     */
    suspend fun initialize() {
        logger.info("Telemetry service initialized")
    }

    /**
     * Cleanup telemetry service
     */
    suspend fun cleanup() = mutex.withLock {
        // Send any pending events
        sendBatch()
        logger.info("Telemetry service cleaned up")
    }

    /**
     * Set device and app information
     * Initialize telemetry context
     */
    suspend fun setContext(deviceId: String, appVersion: String?, sdkVersion: String) = mutex.withLock {
        this.deviceId = deviceId
        this.appVersion = appVersion
        this.sdkVersion = sdkVersion

        // Start session
        currentSession = SessionTelemetryData(
            sessionId = sessionId,
            startTime = Clock.System.now().toEpochMilliseconds(),
            deviceId = deviceId,
            appVersion = appVersion,
            sdkVersion = sdkVersion
        )

        logger.info("Telemetry context set - Device: $deviceId, App: $appVersion, SDK: $sdkVersion")
    }

    /**
     * End current session
     * Track session completion
     */
    suspend fun endSession() = mutex.withLock {
        currentSession?.let { session ->
            val endTime = Clock.System.now().toEpochMilliseconds()
            val updatedSession = session.copy(
                endTime = endTime,
                duration = endTime - session.startTime
            )

            // Track session completion
            val properties = mapOf(
                "session_duration_ms" to updatedSession.duration.toString(),
                "events_count" to updatedSession.eventsCount.toString()
            )

            trackEvent(TelemetryEventType.CUSTOM_EVENT,
                properties + ("event_name" to "session_ended"))
        }

        // Send final batch
        sendBatch()
    }

    // Private helper methods

    private suspend fun sendBatch() {
        if (pendingEvents.isEmpty()) return

        try {
            val batch = TelemetryBatch(
                events = pendingEvents.toList(),
                deviceId = deviceId ?: "unknown",
                sessionId = sessionId,
                appVersion = appVersion,
                sdkVersion = sdkVersion
            )

            telemetryRepository.sendBatch(batch)
            markEventsSent(pendingEvents.map { it.id })

            pendingEvents.clear()
            lastBatchSent = Clock.System.now().toEpochMilliseconds()

            logger.debug("Telemetry batch sent with ${batch.size} events")

        } catch (e: Exception) {
            logger.error("Failed to send telemetry batch: ${e.message}")
            // Keep events in pending list for retry
        }
    }

    private suspend fun sendPendingBatches() {
        mutex.withLock {
            val timeSinceLastBatch = Clock.System.now().toEpochMilliseconds() - lastBatchSent
            if (pendingEvents.isNotEmpty() && timeSinceLastBatch >= batchTimeoutMs) {
                sendBatch()
            }
        }
    }
}
