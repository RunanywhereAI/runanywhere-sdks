package com.runanywhere.sdk.services.configuration

import com.runanywhere.sdk.data.models.ConfigurationData

/**
 * Configuration Service Protocol
 * One-to-one translation from iOS ConfigurationServiceProtocol
 * Defines the contract for configuration management
 */
interface ConfigurationServiceProtocol {

    /**
     * Load configuration on launch with fallback chain
     * Priority: Remote → Database → Consumer → Defaults
     * Equivalent to iOS: func loadConfigurationOnLaunch(apiKey: String) async -> ConfigurationData
     */
    suspend fun loadConfigurationOnLaunch(apiKey: String): ConfigurationData

    /**
     * Set consumer-provided configuration overrides
     * Equivalent to iOS: func setConsumerConfiguration(_ config: ConfigurationData) async throws
     */
    suspend fun setConsumerConfiguration(config: ConfigurationData)

    /**
     * Update configuration with functional transform
     * Equivalent to iOS: func updateConfiguration(_ updates: (ConfigurationData) -> ConfigurationData) async
     */
    suspend fun updateConfiguration(updates: (ConfigurationData) -> ConfigurationData)

    /**
     * Sync configuration to cloud storage
     * Equivalent to iOS: func syncToCloud() async throws
     */
    suspend fun syncToCloud()

    /**
     * Get current configuration
     * Equivalent to iOS computed property: var currentConfiguration: ConfigurationData? { get }
     */
    suspend fun getCurrentConfiguration(): ConfigurationData?

    /**
     * Force refresh configuration from remote
     * Equivalent to iOS: func refreshFromRemote() async throws
     */
    suspend fun refreshFromRemote()

    /**
     * Reset configuration to defaults
     * Equivalent to iOS: func resetToDefaults() async
     */
    suspend fun resetToDefaults()
}
