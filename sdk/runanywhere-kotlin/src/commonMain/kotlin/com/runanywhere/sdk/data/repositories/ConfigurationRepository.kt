package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.models.ConfigurationData

/**
 * Configuration Repository Interface
 * Defines operations for configuration data persistence
 */
interface ConfigurationRepository {
    suspend fun getConfiguration(): ConfigurationData?
    suspend fun saveConfiguration(configuration: ConfigurationData)
    suspend fun clearConfiguration()
}
