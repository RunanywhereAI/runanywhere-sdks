package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.ConfigurationSource
import com.runanywhere.sdk.foundation.SDKLogger
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString

/**
 * JVM implementation of ConfigurationRepository using file system storage
 * Matches iOS ConfigurationRepositoryImpl interface patterns
 */
class ConfigurationRepositoryImpl : ConfigurationRepository {

    private val logger = SDKLogger("ConfigurationRepository")
    private val configFile = File(System.getProperty("user.home"), ".runanywhere/config.json")
    private val consumerConfigFile = File(System.getProperty("user.home"), ".runanywhere/consumer-config.json")
    private var consumerConfig: ConfigurationData? = null

    private val json = Json {
        prettyPrint = true
        ignoreUnknownKeys = true
    }

    init {
        // Ensure config directory exists
        configFile.parentFile?.mkdirs()
    }

    override suspend fun fetchRemoteConfiguration(apiKey: String): ConfigurationData? {
        return try {
            logger.debug("Fetching remote configuration for API key: ${apiKey.take(8)}...")
            // For JVM, we don't implement remote fetching by default
            // This would be implemented with actual HTTP client calls
            null
        } catch (e: Exception) {
            logger.error("Failed to fetch remote configuration", e)
            null
        }
    }

    override suspend fun getLocalConfiguration(): ConfigurationData? {
        return try {
            if (configFile.exists()) {
                val jsonContent = configFile.readText()
                json.decodeFromString<ConfigurationData>(jsonContent)
            } else {
                null
            }
        } catch (e: Exception) {
            logger.error("Failed to get local configuration from file", e)
            null
        }
    }

    override suspend fun saveLocalConfiguration(configuration: ConfigurationData) {
        try {
            val jsonContent = json.encodeToString(configuration)
            configFile.writeText(jsonContent)
            logger.debug("Configuration saved to file: ${configFile.absolutePath}")
        } catch (e: Exception) {
            logger.error("Failed to save local configuration to file", e)
            throw e
        }
    }

    override suspend fun getConsumerConfiguration(): ConfigurationData? {
        return try {
            consumerConfig ?: run {
                if (consumerConfigFile.exists()) {
                    val jsonContent = consumerConfigFile.readText()
                    json.decodeFromString<ConfigurationData>(jsonContent).also {
                        consumerConfig = it
                    }
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            logger.error("Failed to get consumer configuration", e)
            null
        }
    }

    override suspend fun setConsumerConfiguration(configuration: ConfigurationData) {
        try {
            val consumerConfigData = configuration.copy(source = ConfigurationSource.CONSUMER)
            consumerConfig = consumerConfigData

            // Also save to file for persistence
            val jsonContent = json.encodeToString(consumerConfigData)
            consumerConfigFile.writeText(jsonContent)
            logger.debug("Consumer configuration saved")
        } catch (e: Exception) {
            logger.error("Failed to set consumer configuration", e)
            throw e
        }
    }

    override fun getSDKDefaultConfiguration(): ConfigurationData {
        return ConfigurationData.sdkDefaults("default-api-key")
    }

    override suspend fun syncToRemote(configuration: ConfigurationData) {
        try {
            logger.debug("Syncing configuration to remote: ${configuration.id}")
            // For JVM, we don't implement remote syncing by default
            // This would be implemented with actual HTTP client calls
        } catch (e: Exception) {
            logger.error("Failed to sync configuration to remote", e)
            throw e
        }
    }

    // Legacy methods for backward compatibility
    override suspend fun getConfiguration(): ConfigurationData? {
        return getLocalConfiguration()
    }

    override suspend fun saveConfiguration(configuration: ConfigurationData) {
        return saveLocalConfiguration(configuration)
    }

    override suspend fun clearConfiguration() {
        try {
            if (configFile.exists()) {
                configFile.delete()
            }
            if (consumerConfigFile.exists()) {
                consumerConfigFile.delete()
            }
            consumerConfig = null
            logger.info("Configuration files cleared")
        } catch (e: Exception) {
            logger.error("Failed to clear configuration files", e)
            throw e
        }
    }
}
