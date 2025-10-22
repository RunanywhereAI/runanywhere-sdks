package com.runanywhere.sdk.data.sources

import com.runanywhere.sdk.data.cache.InMemoryCache
import com.runanywhere.sdk.data.cache.createInMemoryCache
import com.runanywhere.sdk.data.config.CacheConfiguration
import com.runanywhere.sdk.data.errors.RepositoryError
import com.runanywhere.sdk.data.errors.SerializationOperation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes

/**
 * Local data source implementation using in-memory cache.
 * Provides persistent local storage with optional serialization support.
 */
class CacheLocalDataSource<T : Any>(
    private val cache: InMemoryCache<T>,
    override val configuration: DataSourceConfiguration,
    private val serializer: KSerializer<T>? = null
) : LocalDataSource<T> {

    constructor(
        cacheConfiguration: CacheConfiguration,
        entityName: String,
        serializer: KSerializer<T>? = null
    ) : this(
        cache = createInMemoryCache(cacheConfiguration),
        configuration = DataSourceConfiguration(
            name = "${entityName}LocalDataSource",
            type = DataSourceType.CACHE,
            version = "1.0.0",
            capabilities = setOf(
                DataSourceCapability.CRUD,
                DataSourceCapability.BATCH_OPERATIONS,
                DataSourceCapability.REAL_TIME_OBSERVATION
            )
        ),
        serializer = serializer
    )

    // JSON serializer for state restoration
    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = false
    }

    override suspend fun isAvailable(): Boolean = true

    override suspend fun healthCheck(): DataSourceHealth {
        return try {
            val stats = cache.getStatistics().getOrNull()
            DataSourceHealth(
                isHealthy = true,
                status = HealthStatus.HEALTHY,
                lastCheckTime = System.currentTimeMillis(),
                errors = emptyList(),
                metrics = mapOf(
                    "cache_size" to (stats?.size ?: 0),
                    "cache_hits" to (stats?.hits ?: 0L),
                    "cache_misses" to (stats?.misses ?: 0L),
                    "hit_ratio" to (stats?.hitRatio ?: 0.0)
                )
            )
        } catch (e: Exception) {
            DataSourceHealth(
                isHealthy = false,
                status = HealthStatus.UNHEALTHY,
                lastCheckTime = System.currentTimeMillis(),
                errors = listOf(e.message ?: "Unknown error"),
                metrics = emptyMap()
            )
        }
    }

    override suspend fun save(entity: T): Result<Unit> {
        return try {
            val entityId = extractEntityId(entity)
            cache.put(entityId, entity)
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    override suspend fun saveAll(entities: List<T>): Result<Unit> {
        return try {
            entities.forEach { entity ->
                val entityId = extractEntityId(entity)
                cache.put(entityId, entity).getOrThrow()
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    override suspend fun fetch(id: String): Result<T?> {
        return cache.get(id)
    }

    override suspend fun fetchAll(ids: List<String>): Result<List<T>> {
        return try {
            val results = mutableListOf<T>()
            for (id in ids) {
                val entity = cache.get(id).getOrNull()
                entity?.let { results.add(it) }
            }
            Result.success(results)
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    override suspend fun fetchAll(): Result<List<T>> {
        return cache.values()
    }

    override suspend fun delete(id: String): Result<Unit> {
        return try {
            cache.remove(id)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    override suspend fun deleteAll(ids: List<String>): Result<Unit> {
        return try {
            ids.forEach { id ->
                cache.remove(id).getOrThrow()
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    override suspend fun clear(): Result<Unit> {
        return cache.clear()
    }

    override suspend fun count(): Result<Int> {
        return cache.size()
    }

    override suspend fun exists(id: String): Result<Boolean> {
        return cache.contains(id)
    }

    override fun observeAll(): Flow<List<T>> {
        return cache.changes.map {
            cache.values().getOrElse { emptyList() }
        }
    }

    override fun observe(id: String): Flow<T?> {
        return cache.changes.map {
            cache.get(id).getOrNull()
        }
    }

    override suspend fun getStorageInfo(): Result<StorageInfo> {
        return try {
            val stats = cache.getStatistics().getOrThrow()
            val keys = cache.keys().getOrThrow()

            Result.success(StorageInfo(
                totalSize = estimateStorageSize(),
                usedSize = estimateStorageSize(),
                availableSize = Long.MAX_VALUE, // In-memory has no hard limit
                entityCount = stats.size,
                lastModified = System.currentTimeMillis(),
                metadata = mapOf(
                    "cache_hits" to stats.hits,
                    "cache_misses" to stats.misses,
                    "hit_ratio" to stats.hitRatio,
                    "evictions" to stats.evictions
                )
            ))
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Serialize cache state to string for persistence
     */
    suspend fun serializeState(): Result<String> {
        return try {
            if (serializer == null) {
                return Result.failure(RepositoryError.SerializationError(
                    entityType = configuration.name,
                    operation = SerializationOperation.SERIALIZE,
                    cause = IllegalStateException("No serializer provided")
                ))
            }

            val values = cache.values().getOrThrow()
            val serializedValues = values.map { entity ->
                json.encodeToString(serializer, entity)
            }

            val stateData = mapOf(
                "version" to configuration.version,
                "timestamp" to System.currentTimeMillis(),
                "entities" to serializedValues
            )

            Result.success(json.encodeToString(stateData))
        } catch (e: Exception) {
            Result.failure(RepositoryError.SerializationError(
                entityType = configuration.name,
                operation = SerializationOperation.SERIALIZE,
                cause = e
            ))
        }
    }

    /**
     * Restore cache state from serialized string
     */
    suspend fun restoreState(serializedState: String): Result<Unit> {
        return try {
            if (serializer == null) {
                return Result.failure(RepositoryError.SerializationError(
                    entityType = configuration.name,
                    operation = SerializationOperation.DESERIALIZE,
                    cause = IllegalStateException("No serializer provided")
                ))
            }

            // Clear existing cache
            cache.clear().getOrThrow()

            val stateData: Map<String, Any> = json.decodeFromString(serializedState)
            val entities = stateData["entities"] as? List<String> ?: emptyList()

            entities.forEach { serializedEntity ->
                val entity = json.decodeFromString(serializer, serializedEntity)
                val entityId = extractEntityId(entity)
                cache.put(entityId, entity).getOrThrow()
            }

            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(RepositoryError.SerializationError(
                entityType = configuration.name,
                operation = SerializationOperation.DESERIALIZE,
                cause = e
            ))
        }
    }

    /**
     * Get cache statistics
     */
    suspend fun getCacheStatistics() = cache.getStatistics()

    /**
     * Clean up expired entries
     */
    suspend fun cleanup() = cache.cleanup()

    /**
     * Extract entity ID from entity - needs to be overridden for specific entity types
     */
    private fun extractEntityId(entity: T): String {
        // Try to extract ID using reflection or common property names
        val entityClass = entity::class

        // Look for common ID property names
        val idProperties = listOf("id", "identifier", "key", "uuid")

        for (propertyName in idProperties) {
            try {
                val property = entityClass.members.find { it.name == propertyName }
                if (property != null) {
                    val value = property.call(entity)
                    if (value != null) {
                        return value.toString()
                    }
                }
            } catch (e: Exception) {
                // Continue to next property
            }
        }

        // Fallback to hash code if no ID property found
        return entity.hashCode().toString()
    }

    /**
     * Estimate storage size in bytes
     */
    private suspend fun estimateStorageSize(): Long {
        // This is a rough estimation - in practice, you'd want more accurate measurement
        return cache.getStatistics().fold({ stats ->
            // Rough estimate: 1KB per entity on average
            stats.size * 1024L
        }, { 0L })
    }
}

/**
 * Factory functions for common data source types
 */

/**
 * Create a local data source with default cache configuration
 */
fun <T : Any> createLocalDataSource(
    entityName: String,
    serializer: KSerializer<T>? = null,
    cacheConfiguration: CacheConfiguration = CacheConfiguration()
): LocalDataSource<T> {
    return CacheLocalDataSource(
        cacheConfiguration = cacheConfiguration,
        entityName = entityName,
        serializer = serializer
    )
}

/**
 * Create a local data source optimized for frequent access
 */
fun <T : Any> createHighPerformanceLocalDataSource(
    entityName: String,
    serializer: KSerializer<T>? = null
): LocalDataSource<T> {
    return CacheLocalDataSource(
        cacheConfiguration = CacheConfiguration(
            maxSize = 1000,
            ttl = 2.hours,
            evictionPolicy = com.runanywhere.sdk.data.config.EvictionPolicy.LRU
        ),
        entityName = entityName,
        serializer = serializer
    )
}

/**
 * Create a local data source optimized for memory-constrained environments
 */
fun <T : Any> createLowMemoryLocalDataSource(
    entityName: String,
    serializer: KSerializer<T>? = null
): LocalDataSource<T> {
    return CacheLocalDataSource(
        cacheConfiguration = CacheConfiguration(
            maxSize = 100,
            ttl = 30.minutes,
            evictionPolicy = com.runanywhere.sdk.data.config.EvictionPolicy.LFU
        ),
        entityName = entityName,
        serializer = serializer
    )
}

/**
 * Extension function to convert exceptions to RepositoryError
 */
private fun Throwable.toRepositoryError(): RepositoryError {
    return when (this) {
        is RepositoryError -> this
        is IllegalArgumentException -> RepositoryError.ValidationError(
            field = "unknown",
            value = null,
            validationRule = message ?: "Invalid argument"
        )
        is IllegalStateException -> RepositoryError.ConfigurationError(
            configKey = "state",
            issue = message ?: "Invalid state"
        )
        else -> RepositoryError.UnknownError(cause = this)
    }
}
