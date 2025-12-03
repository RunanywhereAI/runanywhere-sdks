package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.core.SDKConstants
import com.runanywhere.sdk.data.database.RunAnywhereDatabase
import com.runanywhere.sdk.data.database.entities.TelemetryEventEntity
import com.runanywhere.sdk.data.datasources.RemoteTelemetryDataSource
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.models.TelemetryEventData
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.data.network.NetworkService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Android implementation of TelemetryRepository using Room database
 * Note: database parameter can be either RunAnywhereDatabase or InMemoryDatabase
 * since we only use the telemetryDao() method
 *
 * Updated to support RemoteTelemetryDataSource for production analytics
 */
internal class TelemetryRepositoryImpl(
    private val database: Any, // Will be cast to get telemetryDao
    private val networkService: NetworkService,
    private val remoteTelemetryDataSource: RemoteTelemetryDataSource? = null
) : TelemetryRepository {

    private val logger = SDKLogger("TelemetryRepository")

    private val telemetryDao: com.runanywhere.sdk.data.database.dao.TelemetryDao by lazy {
        when (database) {
            is RunAnywhereDatabase -> database.telemetryDao()
            is com.runanywhere.sdk.data.database.InMemoryDatabase -> database.telemetryDao()
            else -> throw IllegalArgumentException("Unsupported database type")
        }
    }

    override suspend fun saveEvent(event: TelemetryData) {
        try {
            val entity = TelemetryEventEntity.fromTelemetryData(event)
            telemetryDao.insertEvent(entity)
            logger.debug("Telemetry event saved to database with ID: ${event.id}")
        } catch (e: Exception) {
            logger.error("Failed to save telemetry event to database", e)
            throw e
        }
    }

    override suspend fun getAllEvents(): List<TelemetryData> {
        return try {
            telemetryDao.getAllEvents()
                .map { it.toTelemetryData() }
        } catch (e: Exception) {
            logger.error("Failed to get all telemetry events from database", e)
            emptyList()
        }
    }

    override suspend fun getUnsentEvents(): List<TelemetryData> {
        return try {
            telemetryDao.getUnsentEvents()
                .map { it.toTelemetryData() }
        } catch (e: Exception) {
            logger.error("Failed to get unsent telemetry events from database", e)
            emptyList()
        }
    }

    // Additional helper methods (not from interface)
    suspend fun getEventsByTimeRange(startTime: Long, endTime: Long): List<TelemetryData> {
        return try {
            telemetryDao.getEventsByTimeRange(startTime, endTime)
                .map { it.toTelemetryData() }
        } catch (e: Exception) {
            logger.error("Failed to get telemetry events by time range from database", e)
            emptyList()
        }
    }

    suspend fun getEventsByType(type: String): List<TelemetryData> {
        return try {
            telemetryDao.getEventsByType(com.runanywhere.sdk.data.models.TelemetryEventType.valueOf(type))
                .map { it.toTelemetryData() }
        } catch (e: Exception) {
            logger.error("Failed to get telemetry events by type from database", e)
            emptyList()
        }
    }

    override suspend fun markEventsSent(eventIds: List<String>, sentAt: Long) {
        try {
            telemetryDao.markEventsSent(eventIds, sentAt)
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
            val deletedCount = telemetryDao.deleteOldEvents(beforeTimestamp)
            logger.debug("Deleted $deletedCount old telemetry events older than $beforeTimestamp")
        } catch (e: Exception) {
            logger.error("Failed to clear old telemetry events", e)
        }
    }

    override suspend fun sendBatch(batch: TelemetryBatch) = withContext(Dispatchers.IO) {
        runCatching {
            if (batch.events.isEmpty()) {
                logger.debug("No events to send")
                return@runCatching
            }

            logger.debug("Sending batch of ${batch.events.size} events")

            // Submit to remote data source if available (production mode)
            if (remoteTelemetryDataSource != null) {
                remoteTelemetryDataSource.submitBatch(batch)
                    .onSuccess {
                        // Mark events as sent in local database
                        val eventIds = batch.events.map { it.id }
                        markEventsSent(eventIds, System.currentTimeMillis())
                        logger.info("✅ Marked ${eventIds.size} events as sent")
                    }
                    .onFailure { error ->
                        logger.error("❌ Failed to send batch: ${error.message}")
                        // Events remain unsent in database for retry
                        throw error
                    }
                    .getOrThrow()
            } else {
                // Fallback: Just mark as sent (development mode or no remote data source)
                logger.debug("No remote telemetry data source available, marking events as sent locally")
                val eventIds = batch.events.map { it.id }
                markEventsSent(eventIds, System.currentTimeMillis())
                logger.info("Marked ${eventIds.size} events as sent (local only)")
            }
        }.getOrElse { exception ->
            logger.error("Failed to send telemetry batch: ${exception.message}", exception)
            throw exception
        }
    }

    suspend fun getEventCount(): Int {
        return try {
            telemetryDao.getEventCount()
        } catch (e: Exception) {
            logger.error("Failed to get telemetry event count", e)
            0
        }
    }

    suspend fun getUnsentEventCount(): Int {
        return try {
            telemetryDao.getUnsentEventCount()
        } catch (e: Exception) {
            logger.error("Failed to get unsent telemetry event count", e)
            0
        }
    }

    private fun generateEventId(): String {
        return "event_${System.currentTimeMillis()}_${(0..9999).random()}"
    }
}
