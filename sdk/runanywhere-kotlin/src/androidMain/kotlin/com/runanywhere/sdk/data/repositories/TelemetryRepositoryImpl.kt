package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.datasources.RemoteTelemetryDataSource
import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventData
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.utils.SDKConstants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

/**
 * Android implementation of TelemetryRepository using in-memory storage
 * Simple implementation without database dependencies
 */
internal class TelemetryRepositoryImpl(
    private val remoteTelemetryDataSource: RemoteTelemetryDataSource? = null,
) : TelemetryRepository {
    private val logger = SDKLogger("TelemetryRepository")
    private val events = ConcurrentHashMap<String, TelemetryData>()
    private val sentEventIds = ConcurrentHashMap<String, Long>()

    override suspend fun saveEvent(event: TelemetryData) {
        try {
            events[event.id] = event
            logger.debug("Telemetry event saved to memory with ID: ${event.id}")
        } catch (e: Exception) {
            logger.error("Failed to save telemetry event to memory", e)
            throw e
        }
    }

    override suspend fun getAllEvents(): List<TelemetryData> =
        try {
            events.values.toList()
        } catch (e: Exception) {
            logger.error("Failed to get all telemetry events from memory", e)
            emptyList()
        }

    override suspend fun getUnsentEvents(): List<TelemetryData> =
        try {
            events.values.filter { event ->
                !sentEventIds.containsKey(event.id)
            }
        } catch (e: Exception) {
            logger.error("Failed to get unsent telemetry events from memory", e)
            emptyList()
        }

    override suspend fun markEventsSent(
        eventIds: List<String>,
        sentAt: Long,
    ) {
        try {
            eventIds.forEach { eventId ->
                sentEventIds[eventId] = sentAt
            }
            logger.debug("Marked ${eventIds.size} telemetry events as sent")
        } catch (e: Exception) {
            logger.error("Failed to mark telemetry events as sent", e)
            throw e
        }
    }

    override suspend fun saveEventData(event: TelemetryEventData) {
        try {
            val telemetryData =
                TelemetryData(
                    id = event.id,
                    type = event.type,
                    name = event.type.name,
                    properties = event.eventData.mapValues { it.value?.toString() ?: "" },
                    metrics = emptyMap(),
                    sessionId = event.sessionId,
                    userId = null,
                    deviceId = event.deviceId,
                    appVersion = null,
                    sdkVersion = SDKConstants.SDK_VERSION,
                    platform = "Android",
                    osVersion = android.os.Build.VERSION.RELEASE,
                    timestamp = event.timestamp,
                    duration = event.duration,
                    success = event.success,
                    errorMessage = if (!event.success) "Event failed" else null,
                    isSent = false,
                    sentAt = null,
                    retryCount = 0,
                )
            saveEvent(telemetryData)
        } catch (e: Exception) {
            logger.error("Failed to save telemetry event data", e)
            throw e
        }
    }

    override suspend fun clearOldEvents(beforeTimestamp: Long) {
        try {
            val toRemove = events.values.filter { it.timestamp < beforeTimestamp }
            toRemove.forEach { event ->
                events.remove(event.id)
                sentEventIds.remove(event.id)
            }
            logger.debug("Cleared ${toRemove.size} old events before timestamp $beforeTimestamp")
        } catch (e: Exception) {
            logger.error("Failed to clear old telemetry events", e)
        }
    }

    override suspend fun sendBatch(batch: TelemetryBatch) =
        withContext(Dispatchers.IO) {
            runCatching {
                if (batch.events.isEmpty()) {
                    logger.debug("No events to send")
                    return@runCatching
                }

                logger.debug("Sending batch of ${batch.events.size} events")

                if (remoteTelemetryDataSource != null) {
                    val result = remoteTelemetryDataSource.submitBatch(batch)
                    if (result.isSuccess) {
                        val eventIds = batch.events.map { it.id }
                        markEventsSent(eventIds, System.currentTimeMillis())
                        logger.info("Marked ${eventIds.size} events as sent")
                    } else {
                        throw result.exceptionOrNull() ?: Exception("Unknown error submitting batch")
                    }
                } else {
                    logger.warn("No remote telemetry data source available - events will NOT be sent to server!")
                    val eventIds = batch.events.map { it.id }
                    markEventsSent(eventIds, System.currentTimeMillis())
                    logger.warn("Marked ${eventIds.size} events as sent (LOCAL ONLY - not sent to server)")
                }
            }.getOrElse { exception ->
                logger.error("Failed to send telemetry batch: ${exception.message}", exception)
                throw exception
            }
        }

    suspend fun getEventCount(): Int = events.size

    suspend fun getUnsentEventCount(): Int = events.values.count { !sentEventIds.containsKey(it.id) }
}
