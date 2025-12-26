package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.repositories.TelemetryRepositoryImpl

/**
 * Android implementation for creating telemetry repository
 *
 * Uses simple in-memory storage for telemetry events.
 * Events are submitted to the remote telemetry data source when available.
 */
actual fun createTelemetryRepository(): TelemetryRepository {
    // Get RemoteTelemetryDataSource from ServiceContainer if available (production mode)
    val remoteTelemetryDataSource =
        try {
            ServiceContainer.shared.remoteTelemetryDataSource
        } catch (e: UninitializedPropertyAccessException) {
            null // Not available yet or not in production mode
        }

    return TelemetryRepositoryImpl(remoteTelemetryDataSource)
}
