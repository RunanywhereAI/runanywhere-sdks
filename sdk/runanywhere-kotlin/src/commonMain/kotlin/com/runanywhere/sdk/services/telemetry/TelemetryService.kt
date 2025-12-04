package com.runanywhere.sdk.services.telemetry

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.models.SessionTelemetryData
import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventData
import com.runanywhere.sdk.data.models.TelemetryEventType
import com.runanywhere.sdk.data.models.generateUUID
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.sync.SyncCoordinator
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

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
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // Session management
    private val sessionId = generateUUID()
    private var currentSession: SessionTelemetryData? = null

    // Batching configuration - optimized for immediate delivery
    // Events are sent immediately (batch size 1) to prevent data loss on app kill/background
    private val batchSize = 1  // Send immediately on each event
    private val batchTimeoutMs = 500L // 500ms backup flush (in case any events slip through)
    private var pendingEvents = mutableListOf<TelemetryData>()
    private var lastBatchSent = getCurrentTimeMillis()

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
    suspend fun trackEvent(type: TelemetryEventType, properties: Map<String, String> = emptyMap()) =
        mutex.withLock {
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
    suspend fun trackCustomEvent(name: String, properties: Map<String, String> = emptyMap()) =
        mutex.withLock {
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
            telemetryRepository.markEventsSent(eventIds, getCurrentTimeMillis())
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
    suspend fun trackSTTModelLoad(
        modelId: String,
        success: Boolean,
        loadTime: Long,
        modelSizeMB: Long
    ) {
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

    // MARK: - STT (Speech-to-Text) Telemetry
    // Matches iOS TelemetryService STT tracking methods

    /**
     * Track STT model load
     * Matches iOS: trackSTTModelLoad(...)
     */
    suspend fun trackSTTModelLoad(
        modelId: String,
        modelName: String,
        framework: String,
        loadTimeMs: Double,
        modelSizeBytes: Long? = null,
        device: String,
        osVersion: String,
        success: Boolean,
        errorMessage: String? = null
    ) {
        val properties = mutableMapOf<String, String>()
        properties["model_id"] = modelId
        properties["model_name"] = modelName
        properties["framework"] = framework
        properties["load_time_ms"] = String.format("%.1f", loadTimeMs)
        properties["device"] = device
        properties["os_version"] = osVersion
        properties["success"] = success.toString()

        modelSizeBytes?.let { properties["model_size_bytes"] = it.toString() }
        errorMessage?.let { properties["error_message"] = it }

        val eventType = if (success) {
            TelemetryEventType.STT_MODEL_LOADED
        } else {
            TelemetryEventType.STT_MODEL_LOAD_FAILED
        }

        trackEvent(eventType, properties)
    }

    /**
     * Track STT transcription start
     * Matches iOS: trackSTTTranscriptionStarted(...)
     */
    suspend fun trackSTTTranscriptionStarted(
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to sessionId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "stt",  // Add modality field
            "language" to language,
            "device" to device,
            "os_version" to osVersion
        )

        logger.debug("🔍 STT_TRANSCRIPTION_STARTED properties: modality=${properties["modality"]}, model_id=${properties["model_id"]}, model_name=${properties["model_name"]}")
        trackEvent(TelemetryEventType.STT_TRANSCRIPTION_STARTED, properties)
    }

    /**
     * Track STT transcription completion with full metrics
     * Matches iOS: trackSTTTranscriptionCompleted(...)
     */
    suspend fun trackSTTTranscriptionCompleted(
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        audioDurationMs: Double,
        processingTimeMs: Double,
        realTimeFactor: Double,
        wordCount: Int,
        characterCount: Int,
        confidence: Float,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to sessionId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "stt",  // Add modality field
            "language" to language,
            "audio_duration_ms" to String.format("%.1f", audioDurationMs),
            "processing_time_ms" to String.format("%.1f", processingTimeMs),
            "real_time_factor" to String.format("%.3f", realTimeFactor),
            "word_count" to wordCount.toString(),
            "character_count" to characterCount.toString(),
            "confidence" to String.format("%.3f", confidence),
            "device" to device,
            "os_version" to osVersion
        )

        trackEvent(TelemetryEventType.STT_TRANSCRIPTION_COMPLETED, properties)
    }

    /**
     * Track STT transcription failure
     * Matches iOS: trackSTTTranscriptionFailed(...)
     */
    suspend fun trackSTTTranscriptionFailed(
        sessionId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        audioDurationMs: Double,
        processingTimeMs: Double,
        errorMessage: String,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to sessionId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "stt",  // Add modality field
            "language" to language,
            "audio_duration_ms" to String.format("%.1f", audioDurationMs),
            "processing_time_ms" to String.format("%.1f", processingTimeMs),
            "error_message" to errorMessage,
            "device" to device,
            "os_version" to osVersion
        )

        trackEvent(TelemetryEventType.STT_TRANSCRIPTION_FAILED, properties)
    }

    /**
     * Track STT streaming update (for real-time transcription)
     * Matches iOS: trackSTTStreamingUpdate(...)
     */
    suspend fun trackSTTStreamingUpdate(
        sessionId: String,
        modelId: String,
        framework: String,
        partialWordCount: Int,
        elapsedMs: Double
    ) {
        val properties = mapOf(
            "session_id" to sessionId,
            "model_id" to modelId,
            "framework" to framework,
            "partial_word_count" to partialWordCount.toString(),
            "elapsed_ms" to String.format("%.1f", elapsedMs)
        )

        trackEvent(TelemetryEventType.STT_STREAMING_UPDATE, properties)
    }

    // MARK: - TTS (Text-to-Speech) Telemetry
    // Matches iOS TelemetryService TTS tracking methods

    /**
     * Track TTS model load
     * Matches iOS: trackTTSModelLoad(...)
     */
    suspend fun trackTTSModelLoad(
        modelId: String,
        modelName: String,
        framework: String,
        loadTimeMs: Double,
        modelSizeBytes: Long? = null,
        device: String,
        osVersion: String,
        success: Boolean,
        errorMessage: String? = null
    ) {
        val properties = mutableMapOf<String, String>()
        properties["model_id"] = modelId
        properties["model_name"] = modelName
        properties["framework"] = framework
        properties["load_time_ms"] = String.format("%.1f", loadTimeMs)
        properties["device"] = device
        properties["os_version"] = osVersion
        properties["success"] = success.toString()

        modelSizeBytes?.let { properties["model_size_bytes"] = it.toString() }
        errorMessage?.let { properties["error_message"] = it }

        val eventType = if (success) {
            TelemetryEventType.TTS_MODEL_LOADED
        } else {
            TelemetryEventType.TTS_MODEL_LOAD_FAILED
        }

        trackEvent(eventType, properties)
    }

    /**
     * Track TTS synthesis start
     * Matches iOS: trackTTSSynthesisStarted(...)
     */
    suspend fun trackTTSSynthesisStarted(
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        voice: String,
        characterCount: Int,
        speakingRate: Float,
        pitch: Float,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to synthesisId,  // Use session_id for API compatibility
            "synthesis_id" to synthesisId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "tts",
            "language" to language,
            "voice" to voice,
            "character_count" to characterCount.toString(),
            "speaking_rate" to String.format("%.2f", speakingRate),
            "pitch" to String.format("%.2f", pitch),
            "device" to device,
            "os_version" to osVersion
        )

        logger.debug("🔍 TTS_SYNTHESIS_STARTED properties: modality=${properties["modality"]}, model_id=${properties["model_id"]}, model_name=${properties["model_name"]}")
        trackEvent(TelemetryEventType.TTS_SYNTHESIS_STARTED, properties)
    }

    /**
     * Track TTS synthesis completion with full metrics
     * Matches iOS: trackTTSSynthesisCompleted(...)
     */
    suspend fun trackTTSSynthesisCompleted(
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        characterCount: Int,
        audioDurationMs: Double,
        processingTimeMs: Double,
        realTimeFactor: Double,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to synthesisId,  // Use session_id for API compatibility
            "synthesis_id" to synthesisId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "tts",
            "language" to language,
            "character_count" to characterCount.toString(),
            "audio_duration_ms" to String.format("%.1f", audioDurationMs),
            "processing_time_ms" to String.format("%.1f", processingTimeMs),
            "real_time_factor" to String.format("%.3f", realTimeFactor),
            "device" to device,
            "os_version" to osVersion
        )

        trackEvent(TelemetryEventType.TTS_SYNTHESIS_COMPLETED, properties)
    }

    /**
     * Track TTS synthesis failure
     * Matches iOS: trackTTSSynthesisFailed(...)
     */
    suspend fun trackTTSSynthesisFailed(
        synthesisId: String,
        modelId: String,
        modelName: String,
        framework: String,
        language: String,
        characterCount: Int,
        processingTimeMs: Double,
        errorMessage: String,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to synthesisId,  // Use session_id for API compatibility
            "synthesis_id" to synthesisId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "tts",
            "language" to language,
            "character_count" to characterCount.toString(),
            "processing_time_ms" to String.format("%.1f", processingTimeMs),
            "error_message" to errorMessage,
            "device" to device,
            "os_version" to osVersion
        )

        trackEvent(TelemetryEventType.TTS_SYNTHESIS_FAILED, properties)
    }

    // MARK: - LLM Generation Telemetry
    // Matches iOS TelemetryService LLM tracking methods

    /**
     * Track LLM generation start
     * Matches iOS: trackGenerationStarted(...)
     */
    suspend fun trackGenerationStarted(
        generationId: String,
        modelId: String,
        modelName: String,
        framework: String,
        promptTokens: Int,
        maxTokens: Int,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to generationId,  // Use session_id for API compatibility
            "generation_id" to generationId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "llm",
            "prompt_tokens" to promptTokens.toString(),
            "max_tokens" to maxTokens.toString(),
            "device" to device,
            "os_version" to osVersion
        )

        trackEvent(TelemetryEventType.GENERATION_STARTED, properties)
    }

    /**
     * Track LLM generation completion with full metrics
     * Matches iOS: trackGenerationCompleted(...)
     */
    suspend fun trackGenerationCompleted(
        generationId: String,
        modelId: String,
        modelName: String,
        framework: String,
        inputTokens: Int,
        outputTokens: Int,
        totalTimeMs: Double,
        timeToFirstTokenMs: Double,
        tokensPerSecond: Double,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to generationId,  // Use session_id for API compatibility
            "generation_id" to generationId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "llm",
            "input_tokens" to inputTokens.toString(),
            "output_tokens" to outputTokens.toString(),
            "total_tokens" to (inputTokens + outputTokens).toString(),
            "total_time_ms" to String.format("%.1f", totalTimeMs),
            "time_to_first_token_ms" to String.format("%.1f", timeToFirstTokenMs),
            "tokens_per_second" to String.format("%.2f", tokensPerSecond),
            "device" to device,
            "os_version" to osVersion
        )

        trackEvent(TelemetryEventType.GENERATION_COMPLETED, properties)
    }

    /**
     * Track LLM generation failure
     * Matches iOS: trackGenerationFailed(...)
     */
    suspend fun trackGenerationFailed(
        generationId: String,
        modelId: String,
        modelName: String,
        framework: String,
        inputTokens: Int,
        totalTimeMs: Double,
        errorMessage: String,
        device: String,
        osVersion: String
    ) {
        val properties = mapOf(
            "session_id" to generationId,  // Use session_id for API compatibility
            "generation_id" to generationId,
            "model_id" to modelId,
            "model_name" to modelName,
            "framework" to framework,
            "modality" to "llm",
            "input_tokens" to inputTokens.toString(),
            "total_time_ms" to String.format("%.1f", totalTimeMs),
            "error_message" to errorMessage,
            "device" to device,
            "os_version" to osVersion
        )

        trackEvent(TelemetryEventType.GENERATION_FAILED, properties)
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
    suspend fun setContext(deviceId: String, appVersion: String?, sdkVersion: String) =
        mutex.withLock {
            this.deviceId = deviceId
            this.appVersion = appVersion
            this.sdkVersion = sdkVersion

            // Start session
            currentSession = SessionTelemetryData(
                sessionId = sessionId,
                startTime = getCurrentTimeMillis(),
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
            val endTime = getCurrentTimeMillis()
            val updatedSession = session.copy(
                endTime = endTime,
                duration = endTime - session.startTime
            )

            // Track session completion
            val properties = mapOf(
                "session_duration_ms" to updatedSession.duration.toString(),
                "events_count" to updatedSession.eventsCount.toString()
            )

            trackEvent(
                TelemetryEventType.CUSTOM_EVENT,
                properties + ("event_name" to "session_ended")
            )
        }

        // Send final batch
        sendBatch()
    }

    /**
     * Flush all pending telemetry events immediately
     * Call this on app pause/stop/background to ensure events are sent before app is killed
     */
    suspend fun flush() = mutex.withLock {
        logger.info("Flushing telemetry events (${pendingEvents.size} pending)")
        if (pendingEvents.isNotEmpty()) {
            sendBatch()
        }
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
            lastBatchSent = getCurrentTimeMillis()

            logger.debug("Telemetry batch sent with ${batch.size} events")

        } catch (e: Exception) {
            logger.error("Failed to send telemetry batch: ${e.message}")
            // Keep events in pending list for retry
        }
    }

    private suspend fun sendPendingBatches() {
        mutex.withLock {
            val timeSinceLastBatch = getCurrentTimeMillis() - lastBatchSent
            if (pendingEvents.isNotEmpty() && timeSinceLastBatch >= batchTimeoutMs) {
                sendBatch()
            }
        }
    }
}
