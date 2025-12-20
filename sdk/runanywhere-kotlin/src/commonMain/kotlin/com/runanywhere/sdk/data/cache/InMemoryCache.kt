package com.runanywhere.sdk.data.cache

import com.runanywhere.sdk.data.config.CacheConfiguration
import com.runanywhere.sdk.data.config.EvictionPolicy
import com.runanywhere.sdk.data.errors.CacheOperation
import com.runanywhere.sdk.data.errors.RepositoryError
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Thread-safe in-memory cache implementation with LRU eviction, TTL support, and Flow-based observations.
 * Provides comprehensive caching functionality with configurable eviction policies and real-time updates.
 */
class InMemoryCache<T : Any>(
    private val configuration: CacheConfiguration,
) {
    private val mutex = Mutex()
    private val storage = mutableMapOf<String, CacheEntry<T>>()
    private val accessOrder = mutableListOf<String>() // For LRU tracking
    private val frequencyMap = mutableMapOf<String, Int>() // For LFU tracking

    // Flow for real-time observations
    private val _changes = MutableSharedFlow<CacheEvent<T>>(replay = 0)
    val changes: Flow<CacheEvent<T>> = _changes.asSharedFlow()

    // Statistics tracking
    private var stats = CacheStatistics()

    /**
     * Put an item in the cache
     */
    suspend fun put(
        key: String,
        value: T,
    ): Result<Unit> =
        try {
            mutex.withLock {
                val now = System.currentTimeMillis()
                val expiryTime = now + configuration.ttl.inWholeMilliseconds

                // Remove existing entry if present
                if (storage.containsKey(key)) {
                    accessOrder.remove(key)
                }

                val entry =
                    CacheEntry(
                        key = key,
                        value = value,
                        createdAt = now,
                        lastAccessed = now,
                        expiryTime = expiryTime,
                        accessCount = 1,
                    )

                storage[key] = entry
                accessOrder.add(key) // Add to end (most recently used)
                frequencyMap[key] = (frequencyMap[key] ?: 0) + 1

                // Check if eviction is needed
                evictIfNecessary()

                stats =
                    stats.copy(
                        puts = stats.puts + 1,
                        size = storage.size,
                    )

                _changes.tryEmit(CacheEvent.Put(key, value))
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.PUT,
                    cause = e,
                ),
            )
        }

    /**
     * Get an item from the cache
     */
    suspend fun get(key: String): Result<T?> {
        return try {
            mutex.withLock {
                val entry = storage[key]
                val now = System.currentTimeMillis()

                if (entry == null) {
                    stats = stats.copy(misses = stats.misses + 1)
                    return@withLock Result.success(null)
                }

                // Check if entry has expired
                if (entry.expiryTime <= now) {
                    storage.remove(key)
                    accessOrder.remove(key)
                    frequencyMap.remove(key)
                    stats =
                        stats.copy(
                            misses = stats.misses + 1,
                            evictions = stats.evictions + 1,
                            size = storage.size,
                        )
                    _changes.tryEmit(CacheEvent.Expired(key, entry.value))
                    return@withLock Result.success(null)
                }

                // Update access information
                val updatedEntry =
                    entry.copy(
                        lastAccessed = now,
                        accessCount = entry.accessCount + 1,
                    )
                storage[key] = updatedEntry

                // Update LRU order
                accessOrder.remove(key)
                accessOrder.add(key)

                // Update frequency
                frequencyMap[key] = (frequencyMap[key] ?: 0) + 1

                stats = stats.copy(hits = stats.hits + 1)

                Result.success(entry.value)
            }
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.GET,
                    cause = e,
                ),
            )
        }
    }

    /**
     * Remove an item from the cache
     */
    suspend fun remove(key: String): Result<T?> =
        try {
            mutex.withLock {
                val entry = storage.remove(key)
                accessOrder.remove(key)
                frequencyMap.remove(key)

                stats =
                    stats.copy(
                        removes = stats.removes + 1,
                        size = storage.size,
                    )

                entry?.let {
                    _changes.tryEmit(CacheEvent.Remove(key, it.value))
                }

                Result.success(entry?.value)
            }
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.REMOVE,
                    cause = e,
                ),
            )
        }

    /**
     * Clear all items from the cache
     */
    suspend fun clear(): Result<Unit> =
        try {
            mutex.withLock {
                val oldSize = storage.size
                storage.clear()
                accessOrder.clear()
                frequencyMap.clear()

                stats =
                    stats.copy(
                        clears = stats.clears + 1,
                        size = 0,
                        evictions = stats.evictions + oldSize,
                    )

                _changes.tryEmit(CacheEvent.Clear())
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.CLEAR,
                    cause = e,
                ),
            )
        }

    /**
     * Get all keys in the cache
     */
    suspend fun keys(): Result<Set<String>> =
        try {
            mutex.withLock {
                Result.success(storage.keys.toSet())
            }
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.GET,
                    cause = e,
                ),
            )
        }

    /**
     * Get all values in the cache
     */
    suspend fun values(): Result<List<T>> =
        try {
            mutex.withLock {
                val now = System.currentTimeMillis()
                val validEntries = storage.values.filter { it.expiryTime > now }
                Result.success(validEntries.map { it.value })
            }
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.GET,
                    cause = e,
                ),
            )
        }

    /**
     * Check if cache contains a key
     */
    suspend fun contains(key: String): Result<Boolean> =
        try {
            mutex.withLock {
                val entry = storage[key]
                val now = System.currentTimeMillis()

                val exists = entry != null && entry.expiryTime > now
                Result.success(exists)
            }
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.GET,
                    cause = e,
                ),
            )
        }

    /**
     * Get current size of the cache
     */
    suspend fun size(): Result<Int> =
        try {
            mutex.withLock {
                Result.success(storage.size)
            }
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.GET,
                    cause = e,
                ),
            )
        }

    /**
     * Get cache statistics
     */
    suspend fun getStatistics(): Result<CacheStatistics> =
        try {
            mutex.withLock {
                Result.success(stats)
            }
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.GET,
                    cause = e,
                ),
            )
        }

    /**
     * Clean up expired entries
     */
    suspend fun cleanup(): Result<Int> =
        try {
            mutex.withLock {
                val now = System.currentTimeMillis()
                val keysToRemove =
                    storage.entries
                        .filter { it.value.expiryTime <= now }
                        .map { it.key }

                keysToRemove.forEach { key ->
                    val entry = storage.remove(key)
                    accessOrder.remove(key)
                    frequencyMap.remove(key)
                    entry?.let {
                        _changes.tryEmit(CacheEvent.Expired(key, it.value))
                    }
                }

                stats =
                    stats.copy(
                        evictions = stats.evictions + keysToRemove.size,
                        size = storage.size,
                    )

                Result.success(keysToRemove.size)
            }
        } catch (e: Exception) {
            Result.failure(
                RepositoryError.CacheError(
                    cacheOperation = CacheOperation.EVICT,
                    cause = e,
                ),
            )
        }

    /**
     * Evict items if cache is full
     */
    private suspend fun evictIfNecessary() {
        while (storage.size > configuration.maxSize) {
            val keyToEvict =
                when (configuration.evictionPolicy) {
                    EvictionPolicy.LRU -> accessOrder.firstOrNull()
                    EvictionPolicy.LFU -> frequencyMap.minByOrNull { it.value }?.key
                    EvictionPolicy.FIFO -> storage.minByOrNull { it.value.createdAt }?.key
                    EvictionPolicy.RANDOM -> storage.keys.randomOrNull()
                    EvictionPolicy.TTL_BASED -> storage.minByOrNull { it.value.expiryTime }?.key
                }

            keyToEvict?.let { key ->
                val entry = storage.remove(key)
                accessOrder.remove(key)
                frequencyMap.remove(key)

                entry?.let {
                    _changes.tryEmit(CacheEvent.Evicted(key, it.value))
                }

                stats = stats.copy(evictions = stats.evictions + 1)
            }
        }

        stats = stats.copy(size = storage.size)
    }
}

/**
 * Cache entry with metadata
 */
private data class CacheEntry<T>(
    val key: String,
    val value: T,
    val createdAt: Long,
    val lastAccessed: Long,
    val expiryTime: Long,
    val accessCount: Int,
)

/**
 * Cache events for Flow-based observations
 */
sealed class CacheEvent<T> {
    data class Put<T>(
        val key: String,
        val value: T,
    ) : CacheEvent<T>()

    data class Remove<T>(
        val key: String,
        val value: T,
    ) : CacheEvent<T>()

    data class Evicted<T>(
        val key: String,
        val value: T,
    ) : CacheEvent<T>()

    data class Expired<T>(
        val key: String,
        val value: T,
    ) : CacheEvent<T>()

    class Clear<T> : CacheEvent<T>()
}

/**
 * Cache statistics for monitoring and debugging
 */
data class CacheStatistics(
    val hits: Long = 0,
    val misses: Long = 0,
    val puts: Long = 0,
    val removes: Long = 0,
    val evictions: Long = 0,
    val clears: Long = 0,
    val size: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
) {
    /**
     * Calculate hit ratio
     */
    val hitRatio: Double
        get() = if (hits + misses > 0) hits.toDouble() / (hits + misses) else 0.0

    /**
     * Calculate total operations
     */
    val totalOperations: Long
        get() = hits + misses + puts + removes
}

/**
 * Factory function to create configured cache instances
 */
fun <T : Any> createInMemoryCache(configuration: CacheConfiguration): InMemoryCache<T> = InMemoryCache(configuration)
