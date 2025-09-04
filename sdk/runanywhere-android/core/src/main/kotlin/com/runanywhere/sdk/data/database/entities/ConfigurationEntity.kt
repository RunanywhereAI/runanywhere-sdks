package com.runanywhere.sdk.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.TypeConverters
import com.runanywhere.sdk.data.database.converters.ConfigurationConverters
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.ConfigurationSource
import com.runanywhere.sdk.data.models.APIConfiguration
import com.runanywhere.sdk.data.models.GenerationConfiguration
import com.runanywhere.sdk.data.models.RoutingConfiguration
import com.runanywhere.sdk.data.models.StorageConfiguration

/**
 * Configuration Entity
 * One-to-one translation from iOS database schema
 * Maps the configuration table from iOS Migration001_InitialSchema
 */
@Entity(
    tableName = "configuration",
    indices = [
        Index(value = ["source"], name = "idx_configuration_source")
    ]
)
@TypeConverters(ConfigurationConverters::class)
data class ConfigurationEntity(
    @PrimaryKey
    val id: String,

    // Complex nested structures stored as JSON blobs via TypeConverters
    val routing: RoutingConfiguration,
    val analytics: AnalyticsConfiguration, // Will need to create this class
    val generation: GenerationConfiguration,
    val storage: StorageConfiguration,

    // Simple fields
    @ColumnInfo(name = "apiKey")
    val apiKey: String?,

    @ColumnInfo(name = "allowUserOverride", defaultValue = "1")
    val allowUserOverride: Boolean = true,

    @ColumnInfo(name = "source", defaultValue = "'defaults'")
    val source: String = "defaults",

    // Metadata
    @ColumnInfo(name = "createdAt")
    val createdAt: Long,

    @ColumnInfo(name = "updatedAt")
    val updatedAt: Long,

    @ColumnInfo(name = "syncPending", defaultValue = "0")
    val syncPending: Boolean = false
) {
    /**
     * Convert to domain model
     * Maps to ConfigurationData
     */
    fun toDomainModel(): ConfigurationData {
        return ConfigurationData(
            id = id,
            apiKey = apiKey ?: "",
            baseURL = "", // Will be filled from analytics configuration
            environment = com.runanywhere.sdk.data.models.SDKEnvironment.DEVELOPMENT, // Will derive from analytics
            source = ConfigurationSource.valueOf(source.uppercase()),
            lastUpdated = updatedAt,
            routing = routing,
            generation = generation,
            storage = storage,
            api = APIConfiguration(), // Will derive from analytics
            download = com.runanywhere.sdk.data.models.ModelDownloadConfiguration(),
            hardware = null
        )
    }

    companion object {
        /**
         * Create entity from domain model
         */
        fun fromDomainModel(config: ConfigurationData): ConfigurationEntity {
            return ConfigurationEntity(
                id = config.id,
                routing = config.routing,
                analytics = AnalyticsConfiguration(), // Will map from config
                generation = config.generation,
                storage = config.storage,
                apiKey = config.apiKey,
                allowUserOverride = true, // Default value, will be configurable
                source = config.source.name.lowercase(),
                createdAt = System.currentTimeMillis(),
                updatedAt = config.lastUpdated,
                syncPending = false
            )
        }
    }
}

/**
 * Analytics Configuration
 * Matches iOS analytics configuration structure
 * TODO: Move to separate models file if grows large
 */
data class AnalyticsConfiguration(
    val enabled: Boolean = true,
    val enableLiveMetrics: Boolean = true,
    val batchSize: Int = 50,
    val flushInterval: Long = 30_000L, // 30 seconds
    val consent: String = "anonymous"
)
