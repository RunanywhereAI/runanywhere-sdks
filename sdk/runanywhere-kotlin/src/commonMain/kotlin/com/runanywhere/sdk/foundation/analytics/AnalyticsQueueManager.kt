package com.runanywhere.sdk.foundation.analytics

import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventType
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.time.Duration.Companion.seconds

/**
 * Central queue for all analytics - handles batching and retry logic
 *
 * Matches iOS AnalyticsQueueManager functionality
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Analytics/AnalyticsQueueManager.swift
 */
object AnalyticsQueueManager {

    // MARK: - Properties

    private val eventQueue = mutableListOf<AnalyticsEvent>()
    private val queueMutex = Mutex()
    private const val BATCH_SIZE = 50
    private val FLUSH_INTERVAL = 30.seconds
    private var telemetryRepository: TelemetryRepository? = null
    private val logger = SDKLogger("AnalyticsQueue")
    private var flushJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private const val MAX_RETRIES = 3

    // MARK: - Initialization

    init {
        startFlushTimer()
    }

    /**
     * Initialize with telemetry repository
     */
    fun initialize(telemetryRepository: TelemetryRepository) {
        this.telemetryRepository = telemetryRepository
        logger.info("AnalyticsQueueManager initialized")
    }

    /**
     * Enqueue a single analytics event
     */
    suspend fun enqueue(event: AnalyticsEvent) {
        queueMutex.withLock {
            eventQueue.add(event)

            if (eventQueue.size >= BATCH_SIZE) {
                flushBatch()
            }
        }
    }

    /**
     * Enqueue multiple analytics events
     */
    suspend fun enqueueBatch(events: List<AnalyticsEvent>) {
        queueMutex.withLock {
            eventQueue.addAll(events)

            if (eventQueue.size >= BATCH_SIZE) {
                flushBatch()
            }
        }
    }

    /**
     * Force flush all pending events
     */
    suspend fun flush() {
        queueMutex.withLock {
            flushBatch()
        }
    }

    /**
     * Cleanup resources
     */
    fun cleanup() {
        flushJob?.cancel()
        scope.cancel()
    }

    // MARK: - Private Methods

    private fun startFlushTimer() {
        flushJob = scope.launch {
            while (isActive) {
                delay(FLUSH_INTERVAL)
                queueMutex.withLock {
                    flushBatch()
                }
            }
        }
    }

    private suspend fun flushBatch() {
        if (eventQueue.isEmpty()) return

        val batch = eventQueue.take(BATCH_SIZE)
        processBatch(batch)
    }

    private suspend fun processBatch(batch: List<AnalyticsEvent>) = withContext(Dispatchers.IO) {
        // For debugging: log analytics events locally
        batch.forEach { event ->
            logger.debug("📊 Analytics Event: ${event.type}")
        }

        val repository = telemetryRepository
        if (repository == null) {
            logger.error("No telemetry repository configured")
            queueMutex.withLock {
                eventQueue.removeAll(batch)
            }
            return@withContext
        }

        // Convert to telemetry events
        val telemetryEvents = batch.mapNotNull { event ->
            try {
                val jsonData = Json.encodeToString(event.eventData)

                // Map event type string to TelemetryEventType enum
                val eventType = TelemetryEventType.entries.find { it.name.equals(event.type, ignoreCase = true) }
                    ?: TelemetryEventType.CUSTOM_EVENT

                TelemetryData(
                    type = eventType,
                    name = event.type,
                    sessionId = "",
                    deviceId = "",
                    sdkVersion = "",
                    osVersion = "",
                    properties = mapOf("structured_data" to jsonData),
                    timestamp = event.timestamp
                )
            } catch (e: Exception) {
                logger.error("Failed to serialize event data for telemetry: ${e.message}")
                null
            }
        }

        // Send to backend via existing telemetry repository with retry
        var success = false
        var attempt = 0

        while (attempt < MAX_RETRIES && !success) {
            try {
                // Send each event through telemetry repository
                telemetryEvents.forEach { telemetryData ->
                    repository.saveEvent(telemetryData)
                }

                success = true
                queueMutex.withLock {
                    eventQueue.removeAll(batch)
                }

            } catch (e: Exception) {
                attempt++
                if (attempt < MAX_RETRIES) {
                    // Exponential backoff: 2^attempt seconds
                    val delaySeconds = (1 shl attempt).toLong() // 2, 4, 8 seconds
                    delay(delaySeconds.seconds)
                } else {
                    logger.error("Failed to send batch after $MAX_RETRIES attempts: ${e.message}")
                    queueMutex.withLock {
                        eventQueue.removeAll(batch)
                    }
                }
            }
        }
    }
}

/**
 * Base interface for analytics events
 */
interface AnalyticsEvent {
    val type: String
    val eventData: Any
    val timestamp: Long
}

/**
 * Base protocol for all structured event data
 */
interface AnalyticsEventData
