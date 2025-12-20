package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.data.database.InMemoryDatabase
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.network.NetworkServiceFactory
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.repositories.TelemetryRepositoryImpl

/**
 * Android implementation for creating telemetry repository
 * Using in-memory database for now - can be easily swapped with real Room database
 * by changing InMemoryDatabase.getInstance() to RunAnywhereDatabase.getDatabase(context)
 *
 * NOTE: In development mode with Supabase, analytics go directly via SupabaseClient,
 * so NetworkService is not needed. We create a mock NetworkService to avoid errors.
 */
actual fun createTelemetryRepository(): TelemetryRepository {
    // Get the in-memory database instance
    // TODO: Replace with RunAnywhereDatabase.getDatabase(context) when ready for production
    val database = InMemoryDatabase.getInstance()

    // Create a mock network service for development mode
    // In development mode, analytics are submitted directly to Supabase via AnalyticsService
    // so this NetworkService is not actually used for analytics
    val networkService =
        NetworkServiceFactory.create(
            environment = SDKEnvironment.DEVELOPMENT, // Use DEVELOPMENT to avoid base URL requirement
        )

    // Get RemoteTelemetryDataSource from ServiceContainer if available (production mode)
    val remoteTelemetryDataSource =
        try {
            com.runanywhere.sdk.foundation.ServiceContainer.shared.remoteTelemetryDataSource
        } catch (e: UninitializedPropertyAccessException) {
            null // Not available yet or not in production mode
        }

    return TelemetryRepositoryImpl(database, networkService, remoteTelemetryDataSource)
}
