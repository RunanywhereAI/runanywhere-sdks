package com.runanywhere.sdk.services.configuration

import com.runanywhere.sdk.data.models.ConfigurationData

/**
 * Protocol for configuration services
 * Exact match to iOS ConfigurationServiceProtocol
 */
interface ConfigurationServiceProtocol {

    /**
     * Get current configuration
     * Exact match to iOS getConfiguration() method
     */
    suspend fun getCurrentConfiguration(): ConfigurationData?

    /**
     * Ensure configuration is loaded
     * Exact match to iOS ensureConfigurationLoaded() method
     */
    suspend fun ensureConfigurationLoaded()

    /**
     * Update configuration with functional transform
     * Exact match to iOS updateConfiguration method
     */
    suspend fun updateConfiguration(updates: (ConfigurationData) -> ConfigurationData)

    /**
     * Sync configuration to cloud storage
     * Exact match to iOS syncToCloud() method
     */
    suspend fun syncToCloud()

    // Simple configuration methods
    /**
     * Load configuration on app launch with simple fallback
     * Exact match to iOS loadConfigurationOnLaunch method
     */
    suspend fun loadConfigurationOnLaunch(apiKey: String): ConfigurationData

    /**
     * Set consumer configuration override
     * Exact match to iOS setConsumerConfiguration method
     */
    suspend fun setConsumerConfiguration(config: ConfigurationData)

    // Legacy methods for compatibility
    /**
     * Legacy method for compatibility
     * Maps to loadConfigurationOnLaunch
     */
    suspend fun loadConfigurationWithFallback(apiKey: String): ConfigurationData

    /**
     * Legacy method for compatibility
     */
    suspend fun clearCache()

    /**
     * Legacy method for compatibility
     */
    suspend fun startBackgroundSync(apiKey: String)
}
