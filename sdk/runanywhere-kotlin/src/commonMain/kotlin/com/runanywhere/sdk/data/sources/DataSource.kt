package com.runanywhere.sdk.data.sources

import com.runanywhere.sdk.data.errors.RepositoryError
import kotlinx.coroutines.flow.Flow

/**
 * Base data source interface providing fundamental data operations.
 * Supports both synchronous and asynchronous data access patterns.
 *
 * @param T The type of entities managed by this data source
 */
interface DataSource<T : Any> {
    /**
     * Check if the data source is available and ready for operations
     */
    suspend fun isAvailable(): Boolean

    /**
     * Perform health check on the data source
     */
    suspend fun healthCheck(): DataSourceHealth

    /**
     * Get configuration information about the data source
     */
    val configuration: DataSourceConfiguration
}

/**
 * Local data source interface for persistent storage operations.
 * Provides CRUD operations with Flow-based observation capabilities.
 */
interface LocalDataSource<T : Any> : DataSource<T> {
    /**
     * Save an entity to local storage
     */
    suspend fun save(entity: T): Result<Unit>

    /**
     * Save multiple entities in a batch operation
     */
    suspend fun saveAll(entities: List<T>): Result<Unit>

    /**
     * Fetch an entity by its identifier
     */
    suspend fun fetch(id: String): Result<T?>

    /**
     * Fetch multiple entities by their identifiers
     */
    suspend fun fetchAll(ids: List<String>): Result<List<T>>

    /**
     * Fetch all entities from local storage
     */
    suspend fun fetchAll(): Result<List<T>>

    /**
     * Delete an entity by its identifier
     */
    suspend fun delete(id: String): Result<Unit>

    /**
     * Delete multiple entities by their identifiers
     */
    suspend fun deleteAll(ids: List<String>): Result<Unit>

    /**
     * Clear all entities from local storage
     */
    suspend fun clear(): Result<Unit>

    /**
     * Get the count of entities in local storage
     */
    suspend fun count(): Result<Int>

    /**
     * Check if an entity exists by its identifier
     */
    suspend fun exists(id: String): Result<Boolean>

    /**
     * Observe changes to all entities
     */
    fun observeAll(): Flow<List<T>>

    /**
     * Observe changes to a specific entity
     */
    fun observe(id: String): Flow<T?>

    /**
     * Get storage statistics and information
     */
    suspend fun getStorageInfo(): Result<StorageInfo>
}

/**
 * Remote data source interface for network operations.
 * Handles data synchronization with remote services.
 */
interface RemoteDataSource<T : Any> : DataSource<T> {
    /**
     * Fetch an entity from remote source
     */
    suspend fun fetchRemote(id: String): Result<T?>

    /**
     * Fetch multiple entities from remote source
     */
    suspend fun fetchAllRemote(ids: List<String>): Result<List<T>>

    /**
     * Fetch all entities from remote source
     */
    suspend fun fetchAllRemote(): Result<List<T>>

    /**
     * Push an entity to remote source
     */
    suspend fun pushRemote(entity: T): Result<T>

    /**
     * Push multiple entities to remote source
     */
    suspend fun pushAllRemote(entities: List<T>): Result<List<T>>

    /**
     * Delete an entity on remote source
     */
    suspend fun deleteRemote(id: String): Result<Unit>

    /**
     * Sync entities with remote source
     */
    suspend fun sync(localEntities: List<T>): Result<SyncResult<T>>

    /**
     * Get network connectivity status
     */
    suspend fun getNetworkStatus(): Result<NetworkStatus>
}

/**
 * Data source configuration containing metadata and settings
 */
data class DataSourceConfiguration(
    val name: String,
    val type: DataSourceType,
    val version: String,
    val capabilities: Set<DataSourceCapability>,
    val metadata: Map<String, Any> = emptyMap(),
)

/**
 * Types of data sources
 */
enum class DataSourceType {
    CACHE,
    LOCAL_STORAGE,
    NETWORK,
    HYBRID,
}

/**
 * Capabilities supported by data sources
 */
enum class DataSourceCapability {
    CRUD,
    BATCH_OPERATIONS,
    REAL_TIME_OBSERVATION,
    OFFLINE_SUPPORT,
    SYNC,
    SEARCH,
    INDEXING,
    TRANSACTIONS,
}

/**
 * Health status of a data source
 */
data class DataSourceHealth(
    val isHealthy: Boolean,
    val status: HealthStatus,
    val lastCheckTime: Long,
    val errors: List<String> = emptyList(),
    val metrics: Map<String, Any> = emptyMap(),
)

/**
 * Health status levels
 */
enum class HealthStatus {
    HEALTHY,
    DEGRADED,
    UNHEALTHY,
    UNKNOWN,
}

/**
 * Storage information and statistics
 */
data class StorageInfo(
    val totalSize: Long,
    val usedSize: Long,
    val availableSize: Long,
    val entityCount: Int,
    val lastModified: Long,
    val metadata: Map<String, Any> = emptyMap(),
)

/**
 * Network connectivity status
 */
data class NetworkStatus(
    val isConnected: Boolean,
    val connectionType: ConnectionType,
    val latency: Long = -1,
    val bandwidth: Long = -1,
)

/**
 * Network connection types
 */
enum class ConnectionType {
    WIFI,
    CELLULAR,
    ETHERNET,
    UNKNOWN,
    NONE,
}

/**
 * Result of a sync operation
 */
data class SyncResult<T>(
    val synced: List<T>,
    val conflicts: List<SyncConflict<T>>,
    val errors: List<RepositoryError>,
    val statistics: SyncStatistics,
)

/**
 * Represents a synchronization conflict
 */
data class SyncConflict<T>(
    val localEntity: T,
    val remoteEntity: T,
    val conflictType: ConflictType,
    val field: String? = null,
)

/**
 * Types of synchronization conflicts
 */
enum class ConflictType {
    MODIFICATION_CONFLICT,
    DELETION_CONFLICT,
    CREATION_CONFLICT,
    VERSION_CONFLICT,
}

/**
 * Statistics about a sync operation
 */
data class SyncStatistics(
    val totalProcessed: Int,
    val successful: Int,
    val failed: Int,
    val conflicts: Int,
    val duration: Long,
    val timestamp: Long,
)
