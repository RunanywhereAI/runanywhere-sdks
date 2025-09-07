package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.database.RunAnywhereDatabase
import com.runanywhere.sdk.data.database.entities.ConfigurationEntity
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.ConfigurationSource
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.repositories.ConfigurationRepository
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.network.NetworkService

/**
 * Android implementation of ConfigurationRepository using Room database
 */
class ConfigurationRepositoryImpl(
    private val database: RunAnywhereDatabase,
    private val networkService: NetworkService
) : ConfigurationRepository {

    private val logger = SDKLogger("ConfigurationRepository")

    override suspend fun getConfiguration(): ConfigurationData? {
        return try {
            val entity = database.configurationDao().getCurrentConfiguration()
            entity?.toConfigurationData()
        } catch (e: Exception) {
            logger.error("Failed to get configuration from database", e)
            null
        }
    }

    // Additional helper methods (not from interface)
    suspend fun getConfigurationByEnvironment(environment: SDKEnvironment): ConfigurationData? {
        return try {
            val entity = database.configurationDao().getConfigurationByEnvironment(environment)
            entity?.toConfigurationData()
        } catch (e: Exception) {
            logger.error("Failed to get configuration by environment from database", e)
            null
        }
    }

    suspend fun getConfigurationBySource(source: ConfigurationSource): ConfigurationData? {
        return try {
            val entity = database.configurationDao().getConfigurationBySource(source)
            entity?.toConfigurationData()
        } catch (e: Exception) {
            logger.error("Failed to get configuration by source from database", e)
            null
        }
    }

    suspend fun getAllConfigurations(): List<ConfigurationData> {
        return try {
            database.configurationDao().getAllConfigurations()
                .map { it.toConfigurationData() }
        } catch (e: Exception) {
            logger.error("Failed to get all configurations from database", e)
            emptyList()
        }
    }

    override suspend fun saveConfiguration(configuration: ConfigurationData) {
        try {
            val entity = ConfigurationEntity.fromConfigurationData(configuration)
            database.configurationDao().insertConfiguration(entity)
            logger.debug("Configuration saved to database with ID: ${configuration.id}")
        } catch (e: Exception) {
            logger.error("Failed to save configuration to database", e)
            throw e
        }
    }

    // Additional helper method (not from interface)
    suspend fun updateConfiguration(configuration: ConfigurationData) {
        try {
            val entity = ConfigurationEntity.fromConfigurationData(configuration)
            database.configurationDao().updateConfiguration(entity)
            logger.debug("Configuration updated in database with ID: ${configuration.id}")
        } catch (e: Exception) {
            logger.error("Failed to update configuration in database", e)
            throw e
        }
    }

    suspend fun deleteConfiguration(configurationId: String) {
        try {
            database.configurationDao().deleteConfigurationById(configurationId)
            logger.debug("Configuration deleted from database with ID: $configurationId")
        } catch (e: Exception) {
            logger.error("Failed to delete configuration from database", e)
            throw e
        }
    }

    override suspend fun clearConfiguration() {
        try {
            database.configurationDao().deleteAllConfigurations()
            logger.info("All configurations cleared from database")
        } catch (e: Exception) {
            logger.error("Failed to clear configurations from database", e)
            throw e
        }
    }

    suspend fun getConfigurationCount(): Int {
        return try {
            database.configurationDao().getConfigurationCount()
        } catch (e: Exception) {
            logger.error("Failed to get configuration count from database", e)
            0
        }
    }

    suspend fun deleteOldConfigurations(olderThanTimestamp: Long) {
        try {
            database.configurationDao().deleteOldConfigurations(olderThanTimestamp)
            logger.debug("Deleted old configurations older than $olderThanTimestamp")
        } catch (e: Exception) {
            logger.error("Failed to delete old configurations", e)
        }
    }
}
