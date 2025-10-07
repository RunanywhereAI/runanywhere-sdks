package com.runanywhere.sdk.data.database.dao

import androidx.room.*
import com.runanywhere.sdk.data.database.entities.ConfigurationEntity
import com.runanywhere.sdk.data.models.ConfigurationSource
import com.runanywhere.sdk.data.models.SDKEnvironment

/**
 * Configuration DAO
 * Room DAO for configuration data following iOS patterns
 */
@Dao
interface ConfigurationDao {

    @Query("SELECT * FROM configurations ORDER BY last_updated DESC LIMIT 1")
    suspend fun getCurrentConfiguration(): ConfigurationEntity?

    @Query("SELECT * FROM configurations WHERE source = :source ORDER BY last_updated DESC LIMIT 1")
    suspend fun getConfigurationBySource(source: ConfigurationSource): ConfigurationEntity?

    @Query("SELECT * FROM configurations WHERE environment = :environment ORDER BY last_updated DESC LIMIT 1")
    suspend fun getConfigurationByEnvironment(environment: SDKEnvironment): ConfigurationEntity?

    @Query("SELECT * FROM configurations ORDER BY last_updated DESC")
    suspend fun getAllConfigurations(): List<ConfigurationEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertConfiguration(configuration: ConfigurationEntity)

    @Update
    suspend fun updateConfiguration(configuration: ConfigurationEntity)

    @Delete
    suspend fun deleteConfiguration(configuration: ConfigurationEntity)

    @Query("DELETE FROM configurations WHERE id = :id")
    suspend fun deleteConfigurationById(id: String)

    @Query("DELETE FROM configurations")
    suspend fun deleteAllConfigurations()

    @Query("DELETE FROM configurations WHERE last_updated < :timestamp")
    suspend fun deleteOldConfigurations(timestamp: Long)

    @Query("SELECT COUNT(*) FROM configurations")
    suspend fun getConfigurationCount(): Int
}
