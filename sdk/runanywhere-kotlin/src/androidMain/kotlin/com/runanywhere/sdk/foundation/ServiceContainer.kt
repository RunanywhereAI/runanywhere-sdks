package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.repositories.TelemetryRepositoryImpl
import com.runanywhere.sdk.data.database.InMemoryDatabase
import com.runanywhere.sdk.data.network.NetworkServiceFactory
import com.runanywhere.sdk.data.models.SDKEnvironment

/**
 * Android implementation for creating telemetry repository
 * Using in-memory database for now - can be easily swapped with real Room database
 * by changing InMemoryDatabase.getInstance() to RunAnywhereDatabase.getDatabase(context)
 */
actual fun createTelemetryRepository(): TelemetryRepository {
    // Get the in-memory database instance
    // TODO: Replace with RunAnywhereDatabase.getDatabase(context) when ready for production
    val database = InMemoryDatabase.getInstance()

    // Create a network service for telemetry
    val networkService = NetworkServiceFactory.create(
        environment = SDKEnvironment.PRODUCTION,
        baseURL = null,
        apiKey = null
    )

    return TelemetryRepositoryImpl(database, networkService)
}
