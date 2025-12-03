package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.repositories.TelemetryRepositoryImpl

/**
 * JVM implementation for creating telemetry repository
 */
actual fun createTelemetryRepository(): TelemetryRepository {
    // Get RemoteTelemetryDataSource from ServiceContainer if available (production mode)
    val remoteTelemetryDataSource = try {
        ServiceContainer.shared.remoteTelemetryDataSource
    } catch (e: UninitializedPropertyAccessException) {
        null // Not available yet or not in production mode
    }

    return TelemetryRepositoryImpl(remoteTelemetryDataSource)
}
