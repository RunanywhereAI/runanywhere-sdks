package com.runanywhere.sdk.services.analytics

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.APIClient
import com.runanywhere.sdk.network.postJson
import com.runanywhere.sdk.utils.PlatformUtils
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * STT Analytics Service for tracking speech-to-text events
 * Matches iOS AnalyticsService implementation for STT tracking
 */
class STTAnalyticsService(
    private val apiClient: APIClient,
    private val batchSize: Int = 10,
    private val flushIntervalMs: Long = 30_000 // 30 seconds
) {
    private val logger = SDKLogger("STTAnalyticsService")

    // Event queue for batching
    private val eventQueue = Channel<AnalyticsEvent>(Channel.UNLIMITED)
    private val eventBuffer = mutableListOf<AnalyticsEvent>()

    // Coroutine scope for background processing
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var processingJob: Job? = null

    // Session tracking
    private var currentSessionId: String? = null
    private val sessionStartTimes = mutableMapOf<String, Long>()

    init {
        startEventProcessor()
    }

    /**
     * Track transcription started event
     */
    fun trackTranscriptionStarted(
        sessionId: String,
        modelId: String,
        audioFormat: String? = null,
        sampleRate: Int? = null
    ) {
        currentSessionId = sessionId
        sessionStartTimes[sessionId] = getCurrentTimeMillis()

        val event = AnalyticsEvent.TranscriptionStarted(
            sessionId = sessionId,
            modelId = modelId,
            audioFormat = audioFormat,
            sampleRate = sampleRate,
            timestamp = getCurrentTimeMillis(),
            deviceInfo = getBasicDeviceInfo()
        )

        sendEvent(event)
        logger.debug("Tracked transcription started: sessionId=$sessionId, model=$modelId")
    }

    /**
     * Track transcription completed event
     */
    fun trackTranscriptionCompleted(
        sessionId: String,
        duration: Long? = null,
        wordCount: Int,
        confidence: Float,
        language: String? = null
    ) {
        // Calculate duration if not provided
        val calculatedDuration = duration ?: sessionStartTimes[sessionId]?.let {
            getCurrentTimeMillis() - it
        } ?: 0L

        val event = AnalyticsEvent.TranscriptionCompleted(
            sessionId = sessionId,
            duration = calculatedDuration,
            wordCount = wordCount,
            averageConfidence = confidence,
            language = language,
            timestamp = getCurrentTimeMillis()
        )

        sendEvent(event)
        logger.debug("Tracked transcription completed: sessionId=$sessionId, duration=${calculatedDuration}ms, words=$wordCount")

        // Clean up session
        sessionStartTimes.remove(sessionId)
    }

    /**
     * Track transcription error event
     */
    fun trackTranscriptionError(
        sessionId: String,
        errorCode: String,
        errorMessage: String,
        modelId: String? = null
    ) {
        val event = AnalyticsEvent.TranscriptionError(
            sessionId = sessionId,
            errorCode = errorCode,
            errorMessage = errorMessage,
            modelId = modelId,
            timestamp = getCurrentTimeMillis()
        )

        sendEvent(event)
        logger.debug("Tracked transcription error: sessionId=$sessionId, error=$errorCode")

        // Clean up session
        sessionStartTimes.remove(sessionId)
    }

    /**
     * Track VAD (Voice Activity Detection) event
     */
    fun trackVADActivity(
        sessionId: String,
        speechDetected: Boolean,
        energyLevel: Float,
        duration: Long
    ) {
        val event = AnalyticsEvent.VADActivity(
            sessionId = sessionId,
            speechDetected = speechDetected,
            energyLevel = energyLevel,
            duration = duration,
            timestamp = getCurrentTimeMillis()
        )

        sendEvent(event)
    }

    /**
     * Track model download event
     */
    fun trackModelDownload(
        modelId: String,
        downloadSize: Long,
        downloadTime: Long,
        success: Boolean
    ) {
        val event = AnalyticsEvent.ModelDownload(
            modelId = modelId,
            downloadSize = downloadSize,
            downloadTime = downloadTime,
            success = success,
            timestamp = getCurrentTimeMillis()
        )

        sendEvent(event)
        logger.debug("Tracked model download: model=$modelId, size=$downloadSize, success=$success")
    }

    /**
     * Track performance metrics
     */
    fun trackPerformanceMetrics(
        sessionId: String,
        realTimeFactor: Float, // Processing time / audio duration
        memoryUsed: Long,
        cpuUsage: Float? = null
    ) {
        val event = AnalyticsEvent.PerformanceMetrics(
            sessionId = sessionId,
            realTimeFactor = realTimeFactor,
            memoryUsed = memoryUsed,
            cpuUsage = cpuUsage,
            timestamp = getCurrentTimeMillis()
        )

        sendEvent(event)
    }

    /**
     * Send event to queue
     */
    private fun sendEvent(event: AnalyticsEvent) {
        scope.launch {
            try {
                eventQueue.send(event)
            } catch (e: Exception) {
                logger.error("Failed to queue analytics event: ${e.message}")
            }
        }
    }

    /**
     * Start background event processor
     */
    private fun startEventProcessor() {
        processingJob = scope.launch {
            // Periodic flush job
            launch {
                while (isActive) {
                    delay(flushIntervalMs)
                    flushEvents()
                }
            }

            // Event collection job
            launch {
                eventQueue.receiveAsFlow().collect { event ->
                    eventBuffer.add(event)

                    // Flush if buffer is full
                    if (eventBuffer.size >= batchSize) {
                        flushEvents()
                    }
                }
            }
        }

        logger.info("Analytics event processor started")
    }

    /**
     * Flush events to backend
     */
    private suspend fun flushEvents() {
        if (eventBuffer.isEmpty()) return

        val eventsToSend = eventBuffer.toList()
        eventBuffer.clear()

        try {
            val batch = AnalyticsBatch(
                events = eventsToSend,
                deviceId = PlatformUtils.getDeviceId(),
                platform = PlatformUtils.getPlatformName(),
                sdkVersion = "0.1.0",
                timestamp = getCurrentTimeMillis()
            )

            // Send to backend
            apiClient.postJson<AnalyticsBatch, AnalyticsResponse>(
                endpoint = "v1/analytics/events",
                payload = batch,
                requiresAuth = true
            )

            logger.debug("Flushed ${eventsToSend.size} analytics events")

        } catch (e: Exception) {
            logger.error("Failed to flush analytics events: ${e.message}")
            // Re-queue events for retry
            eventsToSend.forEach { sendEvent(it) }
        }
    }

    /**
     * Force flush all pending events
     */
    suspend fun flush() {
        flushEvents()
    }

    /**
     * Shutdown analytics service
     */
    fun shutdown() {
        scope.launch {
            flush()
            processingJob?.cancel()
            eventQueue.close()
        }
        logger.info("Analytics service shutdown")
    }

    /**
     * Get basic device info for analytics
     */
    private fun getBasicDeviceInfo(): Map<String, String> {
        return mapOf(
            "platform" to PlatformUtils.getPlatformName(),
            "os_version" to PlatformUtils.getOSVersion(),
            "device_model" to PlatformUtils.getDeviceModel()
        )
    }
}

/**
 * Analytics event types
 */
@Serializable
sealed class AnalyticsEvent {
    abstract val timestamp: Long

    @Serializable
    data class TranscriptionStarted(
        val sessionId: String,
        val modelId: String,
        val audioFormat: String? = null,
        val sampleRate: Int? = null,
        override val timestamp: Long,
        val deviceInfo: Map<String, String>
    ) : AnalyticsEvent()

    @Serializable
    data class TranscriptionCompleted(
        val sessionId: String,
        val duration: Long,
        val wordCount: Int,
        val averageConfidence: Float,
        val language: String? = null,
        override val timestamp: Long
    ) : AnalyticsEvent()

    @Serializable
    data class TranscriptionError(
        val sessionId: String,
        val errorCode: String,
        val errorMessage: String,
        val modelId: String? = null,
        override val timestamp: Long
    ) : AnalyticsEvent()

    @Serializable
    data class VADActivity(
        val sessionId: String,
        val speechDetected: Boolean,
        val energyLevel: Float,
        val duration: Long,
        override val timestamp: Long
    ) : AnalyticsEvent()

    @Serializable
    data class ModelDownload(
        val modelId: String,
        val downloadSize: Long,
        val downloadTime: Long,
        val success: Boolean,
        override val timestamp: Long
    ) : AnalyticsEvent()

    @Serializable
    data class PerformanceMetrics(
        val sessionId: String,
        val realTimeFactor: Float,
        val memoryUsed: Long,
        val cpuUsage: Float? = null,
        override val timestamp: Long
    ) : AnalyticsEvent()
}

/**
 * Analytics batch for sending to backend
 */
@Serializable
data class AnalyticsBatch(
    val events: List<AnalyticsEvent>,
    val deviceId: String,
    val platform: String,
    val sdkVersion: String,
    val timestamp: Long
)

/**
 * Analytics response from backend
 */
@Serializable
data class AnalyticsResponse(
    val success: Boolean,
    val eventsProcessed: Int
)
