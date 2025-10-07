package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.config.RepositoryConfiguration
import com.runanywhere.sdk.data.config.SyncStrategy
import com.runanywhere.sdk.data.errors.RepositoryError
import com.runanywhere.sdk.data.sources.*
import com.runanywhere.sdk.data.sync.SyncCoordinator
import com.runanywhere.sdk.data.sync.ConflictResolutionHandler
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Abstract base repository providing common functionality for all repositories.
 * Integrates local caching, remote synchronization, and conflict resolution.
 *
 * @param T The entity type managed by this repository
 */
abstract class BaseRepository<T : Any>(
    protected val repositoryId: String,
    protected val localDataSource: LocalDataSource<T>,
    protected val remoteDataSource: RemoteDataSource<T>? = null,
    protected val syncCoordinator: SyncCoordinator? = null,
    protected val configuration: RepositoryConfiguration = RepositoryConfiguration.default,
    protected val coroutineScope: CoroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
) {

    private val mutex = Mutex()
    private var isInitialized = false

    // Conflict resolution handler for this repository
    protected open val conflictResolutionHandler: ConflictResolutionHandler<T>? = null

    // Statistics tracking
    private var repositoryStats = RepositoryStatistics()

    /**
     * Initialize the repository
     */
    suspend fun initialize(): Result<Unit> {
        return try {
            mutex.withLock {
                if (isInitialized) return Result.success(Unit)

                // Register with sync coordinator if available
                if (syncCoordinator != null && remoteDataSource != null) {
                    syncCoordinator.registerRepository(
                        repositoryId = repositoryId,
                        localDataSource = localDataSource,
                        remoteDataSource = remoteDataSource,
                        conflictHandler = conflictResolutionHandler
                    )
                }

                // Perform initialization tasks
                onInitialize()

                isInitialized = true
                Result.success(Unit)
            }
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Override for repository-specific initialization
     */
    protected open suspend fun onInitialize() {
        // Default implementation does nothing
    }

    // CRUD Operations

    /**
     * Save an entity to the repository
     */
    open suspend fun save(entity: T): Result<T> {
        return try {
            // Save to local storage first (cache-first strategy)
            localDataSource.save(entity).getOrThrow()

            // Sync with remote if configured for immediate sync
            if (shouldSyncImmediately()) {
                syncWithRemote(listOf(entity))
            } else if (configuration.sync.enabled) {
                queueForSync(listOf(entity))
            }

            updateStats { copy(writes = writes + 1) }
            Result.success(entity)
        } catch (e: Exception) {
            updateStats { copy(errors = errors + 1) }
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Save multiple entities
     */
    open suspend fun saveAll(entities: List<T>): Result<List<T>> {
        return try {
            localDataSource.saveAll(entities).getOrThrow()

            if (shouldSyncImmediately()) {
                syncWithRemote(entities)
            } else if (configuration.sync.enabled) {
                queueForSync(entities)
            }

            updateStats { copy(writes = writes + entities.size) }
            Result.success(entities)
        } catch (e: Exception) {
            updateStats { copy(errors = errors + 1) }
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Fetch an entity by ID
     */
    open suspend fun fetchById(id: String): Result<T?> {
        return try {
            // Try local first
            val localResult = localDataSource.fetch(id).getOrThrow()

            if (localResult != null) {
                updateStats { copy(cacheHits = cacheHits + 1) }
                Result.success(localResult)
            } else {
                // Try remote if configured
                val remoteResult = if (remoteDataSource != null && shouldFetchFromRemote()) {
                    try {
                        val remote = remoteDataSource.fetchRemote(id).getOrThrow()
                        remote?.let {
                            // Cache the remote result
                            localDataSource.save(it).getOrNull()
                        }
                        remote
                    } catch (e: Exception) {
                        null
                    }
                } else {
                    null
                }

                updateStats {
                    copy(
                        cacheMisses = cacheMisses + 1,
                        reads = reads + 1
                    )
                }
                Result.success(remoteResult)
            }
        } catch (e: Exception) {
            updateStats { copy(errors = errors + 1) }
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Fetch all entities
     */
    open suspend fun fetchAll(): Result<List<T>> {
        return try {
            val localEntities = localDataSource.fetchAll().getOrThrow()
            updateStats { copy(reads = reads + localEntities.size) }
            Result.success(localEntities)
        } catch (e: Exception) {
            updateStats { copy(errors = errors + 1) }
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Delete an entity by ID
     */
    open suspend fun delete(id: String): Result<Unit> {
        return try {
            localDataSource.delete(id).getOrThrow()

            // Delete from remote if configured
            if (remoteDataSource != null && shouldSyncImmediately()) {
                remoteDataSource.deleteRemote(id).getOrNull()
            }

            updateStats { copy(deletes = deletes + 1) }
            Result.success(Unit)
        } catch (e: Exception) {
            updateStats { copy(errors = errors + 1) }
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Clear all entities
     */
    open suspend fun clear(): Result<Unit> {
        return try {
            localDataSource.clear().getOrThrow()
            updateStats { copy(clears = clears + 1) }
            Result.success(Unit)
        } catch (e: Exception) {
            updateStats { copy(errors = errors + 1) }
            Result.failure(e.toRepositoryError())
        }
    }

    // Observable Operations

    /**
     * Observe all entities
     */
    open fun observeAll(): Flow<List<T>> {
        return localDataSource.observeAll()
    }

    /**
     * Observe a specific entity by ID
     */
    open fun observe(id: String): Flow<T?> {
        return localDataSource.observe(id)
    }

    // Sync Operations

    /**
     * Manually trigger sync with remote
     */
    open suspend fun sync(): Result<SyncResult<T>> {
        return try {
            if (remoteDataSource == null) {
                Result.failure(RepositoryError.ConfigurationError(
                    configKey = "remoteDataSource",
                    issue = "Remote data source not configured"
                ))
            } else if (syncCoordinator != null) {
                syncCoordinator.syncImmediate(
                    repositoryId = repositoryId,
                    localDataSource = localDataSource,
                    remoteDataSource = remoteDataSource
                )
            } else {
                // Direct sync without coordinator
                val localEntities = localDataSource.fetchAll().getOrThrow()
                remoteDataSource.sync(localEntities)
            }
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Get sync status if using sync coordinator
     */
    open suspend fun getSyncStatus(): Result<Map<String, Any>> {
        return try {
            if (syncCoordinator != null) {
                val stats = syncCoordinator.getSyncStatistics()
                val activeSyncs = syncCoordinator.getActiveSyncs()

                Result.success(mapOf(
                    "statistics" to stats,
                    "activeSyncs" to activeSyncs,
                    "repositoryId" to repositoryId
                ))
            } else {
                Result.success(mapOf(
                    "syncEnabled" to false,
                    "repositoryId" to repositoryId
                ))
            }
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    // Health and Statistics

    /**
     * Perform health check on repository
     */
    open suspend fun healthCheck(): Result<RepositoryHealth> {
        return try {
            val localHealth = localDataSource.healthCheck()
            val remoteHealth = remoteDataSource?.healthCheck()

            val isHealthy = localHealth.isHealthy && (remoteHealth?.isHealthy != false)
            val errors = localHealth.errors + (remoteHealth?.errors ?: emptyList())

            val health = RepositoryHealth(
                repositoryId = repositoryId,
                isHealthy = isHealthy,
                localDataSourceHealth = localHealth,
                remoteDataSourceHealth = remoteHealth,
                errors = errors,
                lastCheck = System.currentTimeMillis(),
                statistics = repositoryStats
            )

            Result.success(health)
        } catch (e: Exception) {
            Result.failure(e.toRepositoryError())
        }
    }

    /**
     * Get repository statistics
     */
    open suspend fun getStatistics(): RepositoryStatistics {
        return mutex.withLock { repositoryStats }
    }

    // Private Helper Methods

    private fun shouldSyncImmediately(): Boolean {
        return configuration.sync.enabled &&
               configuration.sync.strategy == SyncStrategy.IMMEDIATE &&
               remoteDataSource != null
    }

    private fun shouldFetchFromRemote(): Boolean {
        return remoteDataSource != null &&
               configuration.sync.enabled
    }

    private suspend fun syncWithRemote(entities: List<T>) {
        try {
            if (syncCoordinator != null && remoteDataSource != null) {
                syncCoordinator.queueSync(
                    repositoryId = repositoryId,
                    localDataSource = localDataSource,
                    remoteDataSource = remoteDataSource,
                    entities = entities
                )
            }
        } catch (e: Exception) {
            // Log but don't fail the operation
        }
    }

    private suspend fun queueForSync(entities: List<T>) {
        try {
            if (syncCoordinator != null && remoteDataSource != null) {
                syncCoordinator.queueSync(
                    repositoryId = repositoryId,
                    localDataSource = localDataSource,
                    remoteDataSource = remoteDataSource,
                    entities = entities
                )
            }
        } catch (e: Exception) {
            // Log but don't fail the operation
        }
    }

    private suspend fun updateStats(update: RepositoryStatistics.() -> RepositoryStatistics) {
        mutex.withLock {
            repositoryStats = repositoryStats.update()
        }
    }

    /**
     * Shutdown repository and clean up resources
     */
    open suspend fun shutdown() {
        coroutineScope.cancel()
    }
}

/**
 * Repository health information
 */
data class RepositoryHealth(
    val repositoryId: String,
    val isHealthy: Boolean,
    val localDataSourceHealth: DataSourceHealth,
    val remoteDataSourceHealth: DataSourceHealth?,
    val errors: List<String>,
    val lastCheck: Long,
    val statistics: RepositoryStatistics
)

/**
 * Repository statistics
 */
data class RepositoryStatistics(
    val reads: Long = 0,
    val writes: Long = 0,
    val deletes: Long = 0,
    val clears: Long = 0,
    val cacheHits: Long = 0,
    val cacheMisses: Long = 0,
    val errors: Long = 0,
    val startTime: Long = System.currentTimeMillis()
) {
    /**
     * Calculate cache hit ratio
     */
    val cacheHitRatio: Double
        get() = if (cacheHits + cacheMisses > 0) {
            cacheHits.toDouble() / (cacheHits + cacheMisses)
        } else {
            0.0
        }

    /**
     * Calculate total operations
     */
    val totalOperations: Long
        get() = reads + writes + deletes + clears
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

/**
 * Repository builder for easy configuration
 */
class RepositoryBuilder<T : Any>(private val repositoryId: String) {
    private var localDataSource: LocalDataSource<T>? = null
    private var remoteDataSource: RemoteDataSource<T>? = null
    private var syncCoordinator: SyncCoordinator? = null
    private var configuration: RepositoryConfiguration = RepositoryConfiguration.default
    private var coroutineScope: CoroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    fun withLocalDataSource(dataSource: LocalDataSource<T>) = apply {
        this.localDataSource = dataSource
    }

    fun withRemoteDataSource(dataSource: RemoteDataSource<T>) = apply {
        this.remoteDataSource = dataSource
    }

    fun withSyncCoordinator(coordinator: SyncCoordinator) = apply {
        this.syncCoordinator = coordinator
    }

    fun withConfiguration(config: RepositoryConfiguration) = apply {
        this.configuration = config
    }

    fun withCoroutineScope(scope: CoroutineScope) = apply {
        this.coroutineScope = scope
    }

    fun build(): BaseRepository<T> {
        val localDs = localDataSource
            ?: throw IllegalArgumentException("Local data source is required")

        return object : BaseRepository<T>(
            repositoryId = repositoryId,
            localDataSource = localDs,
            remoteDataSource = remoteDataSource,
            syncCoordinator = syncCoordinator,
            configuration = configuration,
            coroutineScope = coroutineScope
        ) {}
    }
}

/**
 * DSL function for creating repositories
 */
fun <T : Any> repository(
    repositoryId: String,
    block: RepositoryBuilder<T>.() -> Unit
): BaseRepository<T> {
    return RepositoryBuilder<T>(repositoryId).apply(block).build()
}
