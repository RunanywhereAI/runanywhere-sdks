package com.runanywhere.sdk.services.configuration

import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.ConfigurationSource
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.repository.ConfigurationRepository
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.services.sync.SyncCoordinator
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Configuration Service
 * One-to-one translation from iOS Swift Actor to Kotlin with thread-safety
 * Handles configuration loading, updates, and synchronization with fallback chain
 */
class ConfigurationService(
    private val configRepository: ConfigurationRepository,
    private val syncCoordinator: SyncCoordinator?
) : ConfigurationServiceProtocol {

    private val logger = SDKLogger("ConfigurationService")
    private val mutex = Mutex()

    private var currentConfig: ConfigurationData? = null
    private var consumerConfig: ConfigurationData? = null

    /**
     * Load configuration on launch with fallback chain
     * Priority: Remote → Database → Consumer → Defaults
     * Equivalent to iOS: func loadConfigurationOnLaunch(apiKey: String) async -> ConfigurationData
     */
    override suspend fun loadConfigurationOnLaunch(apiKey: String): ConfigurationData = mutex.withLock {
        logger.debug("Loading configuration on launch for API key: ${apiKey.take(8)}...")

        try {
            // Step 1: Try to fetch remote configuration
            val remoteConfig = try {
                logger.debug("Attempting to fetch remote configuration")
                configRepository.fetchRemoteConfiguration(apiKey)
            } catch (e: Exception) {
                logger.warn("Failed to fetch remote configuration: ${e.message}")
                null
            }

            if (remoteConfig != null) {
                logger.info("Using remote configuration")
                currentConfig = remoteConfig
                // Cache it locally
                try {
                    configRepository.saveLocalConfiguration(remoteConfig)
                } catch (e: Exception) {
                    logger.warn("Failed to cache remote configuration: ${e.message}")
                }
                return remoteConfig
            }

            // Step 2: Try to load from database cache
            val cachedConfig = try {
                logger.debug("Attempting to load cached configuration")
                configRepository.getLocalConfiguration()
            } catch (e: Exception) {
                logger.warn("Failed to load cached configuration: ${e.message}")
                null
            }

            if (cachedConfig != null) {
                logger.info("Using cached configuration")
                currentConfig = cachedConfig
                return cachedConfig
            }

            // Step 3: Use consumer configuration if available
            consumerConfig?.let { consumer ->
                logger.info("Using consumer configuration")
                currentConfig = consumer
                return consumer
            }

            // Step 4: Fall back to defaults
            logger.info("Using default configuration")
            val defaultConfig = ConfigurationData.defaultConfiguration(apiKey)
            currentConfig = defaultConfig

            // Try to save default configuration to database for future use
            try {
                configRepository.saveLocalConfiguration(defaultConfig)
            } catch (e: Exception) {
                logger.warn("Failed to save default configuration: ${e.message}")
            }

            return defaultConfig

        } catch (e: Exception) {
            logger.error("Critical error during configuration loading", e)
            // Return defaults as last resort
            val defaultConfig = ConfigurationData.defaultConfiguration(apiKey)
            currentConfig = defaultConfig
            return defaultConfig
        }
    }

    /**
     * Set consumer-provided configuration overrides
     * Equivalent to iOS: func setConsumerConfiguration(_ config: ConfigurationData) async throws
     */
    override suspend fun setConsumerConfiguration(config: ConfigurationData) = mutex.withLock {
        logger.debug("Setting consumer configuration")

        try {
            // Validate configuration
            validateConfiguration(config)

            // Store consumer config
            consumerConfig = config.copy(source = ConfigurationSource.CONSUMER)

            // Update current config if it's not from a higher priority source
            if (currentConfig?.source != ConfigurationSource.REMOTE) {
                currentConfig = consumerConfig

                // Save to database
                configRepository.saveLocalConfiguration(consumerConfig!!)
            }

            logger.info("Consumer configuration set successfully")

        } catch (e: Exception) {
            logger.error("Failed to set consumer configuration", e)
            throw SDKError.ConfigurationError("Failed to set consumer configuration: ${e.message}")
        }
    }

    /**
     * Update configuration with functional transform
     * Equivalent to iOS: func updateConfiguration(_ updates: (ConfigurationData) -> ConfigurationData) async
     */
    override suspend fun updateConfiguration(updates: (ConfigurationData) -> ConfigurationData) = mutex.withLock {
        logger.debug("Updating configuration")

        val current = currentConfig ?: throw SDKError.ConfigurationError("No current configuration available")

        try {
            val updatedConfig = updates(current).copy(
                lastUpdated = Clock.System.now().toEpochMilliseconds()
            )

            // Validate updated configuration
            validateConfiguration(updatedConfig)

            currentConfig = updatedConfig

            // Save to database
            configRepository.saveLocalConfiguration(updatedConfig)

            logger.info("Configuration updated successfully")

        } catch (e: Exception) {
            logger.error("Failed to update configuration", e)
            throw SDKError.ConfigurationError("Failed to update configuration: ${e.message}")
        }
    }

    /**
     * Sync configuration to cloud storage
     * Equivalent to iOS: func syncToCloud() async throws
     */
    override suspend fun syncToCloud() = mutex.withLock {
        logger.debug("Syncing configuration to cloud")

        val current = currentConfig ?: throw SDKError.ConfigurationError("No configuration to sync")

        try {
            // Use sync coordinator if available
            syncCoordinator?.let { coordinator ->
                coordinator.syncConfiguration(current)
            } ?: run {
                // Direct sync without coordinator
                configRepository.syncToRemote(current)
            }

            logger.info("Configuration synced to cloud successfully")

        } catch (e: Exception) {
            logger.error("Failed to sync configuration to cloud", e)
            throw SDKError.NetworkError("Failed to sync configuration: ${e.message}")
        }
    }

    /**
     * Get current configuration
     * Equivalent to iOS computed property: var currentConfiguration: ConfigurationData? { get }
     */
    override suspend fun getCurrentConfiguration(): ConfigurationData? = mutex.withLock {
        return currentConfig
    }

    /**
     * Force refresh configuration from remote
     * Equivalent to iOS: func refreshFromRemote() async throws
     */
    override suspend fun refreshFromRemote() = mutex.withLock {
        logger.debug("Force refreshing configuration from remote")

        val apiKey = currentConfig?.apiKey ?: throw SDKError.ConfigurationError("No API key available")

        try {
            val remoteConfig = configRepository.fetchRemoteConfiguration(apiKey)

            if (remoteConfig != null) {
                currentConfig = remoteConfig
                configRepository.saveLocalConfiguration(remoteConfig)
                logger.info("Configuration refreshed from remote")
            } else {
                logger.warn("No remote configuration available")
            }

        } catch (e: Exception) {
            logger.error("Failed to refresh configuration from remote", e)
            throw SDKError.NetworkError("Failed to refresh configuration: ${e.message}")
        }
    }

    /**
     * Reset configuration to defaults
     * Equivalent to iOS: func resetToDefaults() async
     */
    override suspend fun resetToDefaults() = mutex.withLock {
        logger.debug("Resetting configuration to defaults")

        val apiKey = currentConfig?.apiKey ?: throw SDKError.ConfigurationError("No API key available")

        try {
            val defaultConfig = ConfigurationData.defaultConfiguration(apiKey)
            currentConfig = defaultConfig
            consumerConfig = null

            // Save defaults to database
            configRepository.saveLocalConfiguration(defaultConfig)

            logger.info("Configuration reset to defaults")

        } catch (e: Exception) {
            logger.error("Failed to reset configuration to defaults", e)
            throw SDKError.ConfigurationError("Failed to reset configuration: ${e.message}")
        }
    }

    // Private helper methods

    private fun validateConfiguration(config: ConfigurationData) {
        // Validate API key
        if (config.apiKey.isBlank()) {
            throw SDKError.InvalidAPIKey("API key cannot be blank")
        }

        // Validate base URL
        if (config.baseURL.isBlank()) {
            throw SDKError.ConfigurationError("Base URL cannot be blank")
        }

        // Validate generation parameters
        with(config.generation) {
            if (maxTokens <= 0) {
                throw SDKError.ConfigurationError("Max tokens must be positive")
            }
            if (temperature < 0.0f || temperature > 2.0f) {
                throw SDKError.ConfigurationError("Temperature must be between 0.0 and 2.0")
            }
            if (topP < 0.0f || topP > 1.0f) {
                throw SDKError.ConfigurationError("Top-p must be between 0.0 and 1.0")
            }
        }

        // Validate storage parameters
        with(config.storage) {
            if (cacheSizeMB < 0) {
                throw SDKError.ConfigurationError("Cache size cannot be negative")
            }
            if (modelCacheSizeMB < 0) {
                throw SDKError.ConfigurationError("Model cache size cannot be negative")
            }
        }

        // Additional validations can be added here
        logger.debug("Configuration validation passed")
    }
}
