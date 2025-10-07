package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventData
import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.foundation.SDKLogger
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * JVM implementation of TelemetryRepository using in-memory storage
 * Note: This is a simple implementation for development/testing purposes
 */
class TelemetryRepositoryImpl : TelemetryRepository {

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

    override suspend fun getAllEvents(): List<TelemetryData> {
        return try {
            events.values.toList()
        } catch (e: Exception) {
            logger.error("Failed to get all telemetry events from memory", e)
            emptyList()
        }
    }

    override suspend fun getUnsentEvents(): List<TelemetryData> {
        return try {
            events.values.filter { event ->
                !sentEventIds.containsKey(event.id)
            }
        } catch (e: Exception) {
            logger.error("Failed to get unsent telemetry events from memory", e)
            emptyList()
        }
    }

    override suspend fun markEventsSent(eventIds: List<String>, sentAt: Long) {
        try {
            eventIds.forEach { eventId ->
                sentEventIds[eventId] = sentAt
            }
            logger.debug("Marked ${eventIds.size} events as sent")
        } catch (e: Exception) {
            logger.error("Failed to mark events as sent", e)
        }
    }

    override suspend fun sendBatch(batch: TelemetryBatch) {
        try {
            // For JVM, we'll just mark these as processed
            logger.info("Processing telemetry batch with ${batch.events.size} events (JVM stub implementation)")
            val eventIds = batch.events.map { it.id }
            markEventsSent(eventIds, System.currentTimeMillis())
        } catch (e: Exception) {
            logger.error("Failed to send telemetry batch", e)
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
            logger.error("Failed to clear old events", e)
        }
    }
}
