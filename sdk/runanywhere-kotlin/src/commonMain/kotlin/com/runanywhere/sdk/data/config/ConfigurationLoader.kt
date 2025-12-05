package com.runanywhere.sdk.data.config

import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.serialization.json.Json

/**
 * Loads configuration from JSON files based on environment
 * Optional enhancement - existing ConfigurationService already handles config loading
 * 
 * This provides an alternative way to load environment-specific configs from files:
 * - dev.json for development
 * - staging.json for staging  
 * - prod.json for production
 */
class ConfigurationLoader {
    private val logger = SDKLogger("ConfigurationLoader")
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        prettyPrint = false
    }

    /**
     * Load configuration for the given environment
     * Files: dev.json, staging.json, prod.json
     * 
     * @param environment SDK environment
     * @return ConfigurationData if file exists and is valid, null otherwise
     */
    suspend fun loadConfiguration(environment: SDKEnvironment): ConfigurationData? {
        val configFileName = when (environment) {
            SDKEnvironment.DEVELOPMENT -> "dev.json"
            SDKEnvironment.STAGING -> "staging.json"
            SDKEnvironment.PRODUCTION -> "prod.json"
        }

        return try {
            val configJson = loadResourceFile(configFileName)
            if (configJson.isNotEmpty()) {
                val config = json.decodeFromString<ConfigurationData>(configJson)
                logger.info("✅ Loaded configuration from $configFileName")
                config
            } else {
                logger.debug("Configuration file $configFileName not found, using defaults")
                null
            }
        } catch (e: Exception) {
            logger.warn("Failed to load configuration from $configFileName: ${e.message}")
            null
        }
    }

    /**
     * Load resource file from platform-specific location
     * Delegates to platform-specific implementation
     */
    private suspend fun loadResourceFile(fileName: String): String {
        return com.runanywhere.sdk.data.config.loadResourceFile(fileName)
    }
}

/**
 * Platform-specific resource file loading
 * Expect/actual pattern for platform-specific implementations
 */
internal expect suspend fun loadResourceFile(fileName: String): String

