package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.datasources.RemoteTelemetryDataSource
import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventData
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

/**
 * JVM implementation of TelemetryRepository using in-memory storage
 * Note: This is a simple implementation for development/testing purposes
 *
 * Updated to support RemoteTelemetryDataSource for production analytics
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

    override suspend fun saveEventData(event: TelemetryEventData) {
        // For JVM implementation, we'll convert to TelemetryData or ignore for now
        logger.debug("TelemetryEventData save operation not implemented for JVM")
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
            logger.debug("Marked ${eventIds.size} events as sent")
        } catch (e: Exception) {
            logger.error("Failed to mark events as sent", e)
        }
    }

    override suspend fun sendBatch(batch: TelemetryBatch) =
        withContext(Dispatchers.IO) {
            runCatching {
                if (batch.events.isEmpty()) {
                    logger.debug("No events to send")
                    return@runCatching
                }

                val eventIds = batch.events.map { it.id }
                logger.debug("Sending batch of ${batch.events.size} events")

                // Submit to remote data source if available (production mode)
                if (remoteTelemetryDataSource != null) {
                    remoteTelemetryDataSource.submitBatch(batch).getOrThrow()
                    // Mark events as sent in memory
                    eventIds.forEach { sentEventIds[it] = System.currentTimeMillis() }
                    logger.info("✅ Marked ${eventIds.size} events as sent")
                } else {
                    // Fallback: Just mark as processed (development mode or no remote data source)
                    logger.warn("⚠️ No remote telemetry data source available - events will NOT be sent to server!")
                    logger.warn("⚠️ This means SDK was initialized in DEVELOPMENT mode or baseURL was null")
                    eventIds.forEach { sentEventIds[it] = System.currentTimeMillis() }
                    logger.warn("📦 Marked ${eventIds.size} events as processed (LOCAL ONLY - not sent to server)")
                }
            }.getOrElse { exception ->
                logger.error("Failed to send telemetry batch: ${exception.message}", exception)
                throw exception
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
            logger.error("Failed to clear old events", e)
        }
    }
}
