package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventData

/**
 * Telemetry Repository Interface
 * Defines operations for telemetry data persistence
 */
interface TelemetryRepository {
    suspend fun saveEvent(event: TelemetryData)

    suspend fun saveEventData(event: TelemetryEventData)

    suspend fun getAllEvents(): List<TelemetryData>

    suspend fun getUnsentEvents(): List<TelemetryData>

    suspend fun markEventsSent(
        eventIds: List<String>,
        sentAt: Long,
    )

    suspend fun sendBatch(batch: TelemetryBatch)

    suspend fun clearOldEvents(beforeTimestamp: Long)
}
