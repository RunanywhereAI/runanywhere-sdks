package com.runanywhere.sdk.data.database.dao

import androidx.room.*
import com.runanywhere.sdk.data.database.entities.TelemetryEventEntity
import com.runanywhere.sdk.data.models.TelemetryEventType

/**
 * Telemetry DAO
 * Room DAO for telemetry data following iOS patterns
 */
@Dao
interface TelemetryDao {

    @Query("SELECT * FROM telemetry_events WHERE id = :eventId")
    suspend fun getEventById(eventId: String): TelemetryEventEntity?

    @Query("SELECT * FROM telemetry_events ORDER BY timestamp DESC")
    suspend fun getAllEvents(): List<TelemetryEventEntity>

    @Query("SELECT * FROM telemetry_events WHERE session_id = :sessionId ORDER BY timestamp DESC")
    suspend fun getEventsBySession(sessionId: String): List<TelemetryEventEntity>

    @Query("SELECT * FROM telemetry_events WHERE type = :eventType ORDER BY timestamp DESC")
    suspend fun getEventsByType(eventType: TelemetryEventType): List<TelemetryEventEntity>

    @Query("SELECT * FROM telemetry_events WHERE is_sent = 0 ORDER BY timestamp ASC")
    suspend fun getUnsentEvents(): List<TelemetryEventEntity>

    @Query("SELECT * FROM telemetry_events WHERE is_sent = 1 ORDER BY timestamp DESC")
    suspend fun getSentEvents(): List<TelemetryEventEntity>

    @Query("SELECT * FROM telemetry_events WHERE success = 0 ORDER BY timestamp DESC")
    suspend fun getFailedEvents(): List<TelemetryEventEntity>

    @Query("SELECT * FROM telemetry_events WHERE timestamp BETWEEN :startTime AND :endTime ORDER BY timestamp DESC")
    suspend fun getEventsByTimeRange(startTime: Long, endTime: Long): List<TelemetryEventEntity>

    @Query("SELECT * FROM telemetry_events WHERE device_id = :deviceId ORDER BY timestamp DESC")
    suspend fun getEventsByDevice(deviceId: String): List<TelemetryEventEntity>

    @Query("SELECT * FROM telemetry_events ORDER BY timestamp DESC LIMIT :limit")
    suspend fun getRecentEvents(limit: Int = 100): List<TelemetryEventEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertEvent(event: TelemetryEventEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertEvents(events: List<TelemetryEventEntity>)

    @Update
    suspend fun updateEvent(event: TelemetryEventEntity)

    @Query("""
        UPDATE telemetry_events
        SET is_sent = 1, sent_at = :sentAt
        WHERE id IN (:eventIds)
    """)
    suspend fun markEventsSent(eventIds: List<String>, sentAt: Long)

    @Query("""
        UPDATE telemetry_events
        SET retry_count = retry_count + 1
        WHERE id IN (:eventIds)
    """)
    suspend fun incrementRetryCount(eventIds: List<String>)

    @Delete
    suspend fun deleteEvent(event: TelemetryEventEntity)

    @Query("DELETE FROM telemetry_events WHERE id = :eventId")
    suspend fun deleteEventById(eventId: String)

    @Query("DELETE FROM telemetry_events WHERE id IN (:eventIds)")
    suspend fun deleteEventsByIds(eventIds: List<String>)

    @Query("DELETE FROM telemetry_events")
    suspend fun deleteAllEvents()

    @Query("DELETE FROM telemetry_events WHERE timestamp < :timestamp")
    suspend fun deleteOldEvents(timestamp: Long)

    @Query("DELETE FROM telemetry_events WHERE is_sent = 1 AND sent_at < :timestamp")
    suspend fun deleteOldSentEvents(timestamp: Long)

    @Query("SELECT COUNT(*) FROM telemetry_events")
    suspend fun getEventCount(): Int

    @Query("SELECT COUNT(*) FROM telemetry_events WHERE is_sent = 0")
    suspend fun getUnsentEventCount(): Int

    @Query("SELECT COUNT(*) FROM telemetry_events WHERE success = 0")
    suspend fun getFailedEventCount(): Int

    @Query("SELECT COUNT(*) FROM telemetry_events WHERE type = :eventType")
    suspend fun getEventCountByType(eventType: TelemetryEventType): Int

    @Query("SELECT AVG(duration) FROM telemetry_events WHERE type = :eventType AND duration IS NOT NULL")
    suspend fun getAverageDurationByType(eventType: TelemetryEventType): Double?
}
