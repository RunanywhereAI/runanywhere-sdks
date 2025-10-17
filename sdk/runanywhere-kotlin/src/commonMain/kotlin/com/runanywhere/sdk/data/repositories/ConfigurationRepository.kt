package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.models.ConfigurationData

/**
 * Configuration Repository Interface
 * Exact match to iOS ConfigurationRepositoryImpl interface patterns
 */
interface ConfigurationRepository {
    /**
     * Fetch remote configuration from server
     */
    suspend fun fetchRemoteConfiguration(apiKey: String): ConfigurationData?

    /**
     * Get local configuration from database/storage
     */
    suspend fun getLocalConfiguration(): ConfigurationData?

    /**
     * Save configuration to local storage
     */
    suspend fun saveLocalConfiguration(configuration: ConfigurationData)

    /**
     * Get consumer-provided configuration
     */
    suspend fun getConsumerConfiguration(): ConfigurationData?

    /**
     * Set consumer configuration
     */
    suspend fun setConsumerConfiguration(configuration: ConfigurationData)

    /**
     * Get SDK default configuration
     */
    fun getSDKDefaultConfiguration(): ConfigurationData

    /**
     * Sync configuration to remote storage
     */
    suspend fun syncToRemote(configuration: ConfigurationData)

    // Legacy methods for backward compatibility
    suspend fun getConfiguration(): ConfigurationData? {
        return getLocalConfiguration()
    }

    suspend fun saveConfiguration(configuration: ConfigurationData) {
        return saveLocalConfiguration(configuration)
    }

    suspend fun clearConfiguration() {
        // Implementation specific - clear local storage
    }
}
