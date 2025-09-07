package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.core.SDKConstants
import com.runanywhere.sdk.data.database.RunAnywhereDatabase
import com.runanywhere.sdk.data.database.entities.TelemetryEventEntity
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.models.TelemetryEventData
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.NetworkService

/**
 * Android implementation of TelemetryRepository using Room database
 */
class TelemetryRepositoryImpl(
    private val database: RunAnywhereDatabase,
    private val networkService: NetworkService
) : TelemetryRepository {

    private val logger = SDKLogger("TelemetryRepository")

    override suspend fun saveEvent(event: TelemetryData) {
        try {
            val entity = TelemetryEventEntity.fromTelemetryData(event)
            database.telemetryDao().insertEvent(entity)
            logger.debug("Telemetry event saved to database with ID: ${event.id}")
        } catch (e: Exception) {
            logger.error("Failed to save telemetry event to database", e)
            throw e
        }
    }

    override suspend fun getAllEvents(): List<TelemetryData> {
        return try {
            database.telemetryDao().getAllEvents()
                .map { it.toTelemetryData() }
        } catch (e: Exception) {
            logger.error("Failed to get all telemetry events from database", e)
            emptyList()
        }
    }

    override suspend fun getUnsentEvents(): List<TelemetryData> {
        return try {
            database.telemetryDao().getUnsentEvents()
                .map { it.toTelemetryData() }
        } catch (e: Exception) {
            logger.error("Failed to get unsent telemetry events from database", e)
            emptyList()
        }
    }

    // Additional helper methods (not from interface)
    suspend fun getEventsByTimeRange(startTime: Long, endTime: Long): List<TelemetryData> {
        return try {
            database.telemetryDao().getEventsByTimeRange(startTime, endTime)
                .map { it.toTelemetryData() }
        } catch (e: Exception) {
            logger.error("Failed to get telemetry events by time range from database", e)
            emptyList()
        }
    }

    suspend fun getEventsByType(type: String): List<TelemetryData> {
        return try {
            database.telemetryDao().getEventsByType(com.runanywhere.sdk.data.models.TelemetryEventType.valueOf(type))
                .map { it.toTelemetryData() }
        } catch (e: Exception) {
            logger.error("Failed to get telemetry events by type from database", e)
            emptyList()
        }
    }

    override suspend fun markEventsSent(eventIds: List<String>, sentAt: Long) {
        try {
            database.telemetryDao().markEventsSent(eventIds, sentAt)
            logger.debug("Marked ${eventIds.size} telemetry events as sent")
        } catch (e: Exception) {
            logger.error("Failed to mark telemetry events as sent", e)
            throw e
        }
    }

    override suspend fun saveEventData(event: TelemetryEventData) {
        try {
            // Convert TelemetryEventData to TelemetryData
            val telemetryData = TelemetryData(
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
                retryCount = 0
            )
            saveEvent(telemetryData)
        } catch (e: Exception) {
            logger.error("Failed to save telemetry event data", e)
            throw e
        }
    }

    override suspend fun clearOldEvents(beforeTimestamp: Long) {
        try {
            val deletedCount = database.telemetryDao().deleteOldEvents(beforeTimestamp)
            logger.debug("Deleted $deletedCount old telemetry events older than $beforeTimestamp")
        } catch (e: Exception) {
            logger.error("Failed to clear old telemetry events", e)
        }
    }

    override suspend fun sendBatch(batch: TelemetryBatch) {
        try {
            // Send telemetry batch using generic post method
            networkService.post<TelemetryBatch, Unit>("/telemetry/batch", batch, requiresAuth = true)
            // Mark events as sent
            val eventIds = batch.events.map { it.id }
            markEventsSent(eventIds, System.currentTimeMillis())
            logger.info("Successfully sent batch of ${batch.events.size} telemetry events")
        } catch (e: Exception) {
            logger.error("Failed to send telemetry batch", e)
            throw e
        }
    }

    suspend fun getEventCount(): Int {
        return try {
            database.telemetryDao().getEventCount()
        } catch (e: Exception) {
            logger.error("Failed to get telemetry event count", e)
            0
        }
    }

    suspend fun getUnsentEventCount(): Int {
        return try {
            database.telemetryDao().getUnsentEventCount()
        } catch (e: Exception) {
            logger.error("Failed to get unsent telemetry event count", e)
            0
        }
    }

    private fun generateEventId(): String {
        return "event_${System.currentTimeMillis()}_${(0..9999).random()}"
    }
}
