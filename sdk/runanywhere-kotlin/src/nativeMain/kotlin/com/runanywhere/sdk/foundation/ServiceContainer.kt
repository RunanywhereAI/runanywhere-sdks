package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.repositories.TelemetryRepositoryImpl

/**
 * Native implementation for creating telemetry repository
 */
actual fun createTelemetryRepository(): TelemetryRepository {
    return TelemetryRepositoryImpl()
}
