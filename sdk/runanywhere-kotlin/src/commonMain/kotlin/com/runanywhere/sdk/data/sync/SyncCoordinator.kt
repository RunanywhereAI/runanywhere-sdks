package com.runanywhere.sdk.data.sync

import com.runanywhere.sdk.data.config.SyncConfiguration
import com.runanywhere.sdk.data.config.ConflictResolution
import com.runanywhere.sdk.data.config.SyncStrategy
import com.runanywhere.sdk.data.config.SyncPriority
import com.runanywhere.sdk.data.errors.RepositoryError
import com.runanywhere.sdk.data.sources.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.collections.*

/**
 * Centralized sync coordinator for managing data synchronization across repositories.
 * Handles batch operations, conflict resolution, retry logic, and priority queuing.
 */
class SyncCoordinator(
    private val configuration: SyncConfiguration,
    private val coroutineScope: CoroutineScope
) {

    private val mutex = Mutex()
    private val syncQueue = Channel<SyncOperation>(capacity = Channel.UNLIMITED)
    private val activeSyncs = mutableMapOf<String, SyncStatus>()
    private val conflictResolutionHandlers = mutableMapOf<String, ConflictResolutionHandler<*>>()

    // Statistics and monitoring
    private var syncStatistics = SyncStatistics(0, 0, 0, 0, 0, System.currentTimeMillis())

    // Events for monitoring sync operations
    private val _syncEvents = MutableSharedFlow<SyncEvent>()
    val syncEvents: SharedFlow<SyncEvent> = _syncEvents.asSharedFlow()

    // Background sync processor
    private var syncProcessor: Job? = null

    init {
        startSyncProcessor()
    }

    /**
     * Register a repository for synchronization
     */
    suspend fun <T : Any> registerRepository(
        repositoryId: String,
        localDataSource: LocalDataSource<T>,
        remoteDataSource: RemoteDataSource<T>,
        conflictHandler: ConflictResolutionHandler<T>? = null
    ) {
        mutex.withLock {
            conflictHandler?.let {
                @Suppress("UNCHECKED_CAST")
                conflictResolutionHandlers[repositoryId] = it as ConflictResolutionHandler<Any>
            }

            _syncEvents.tryEmit(SyncEvent.RepositoryRegistered(repositoryId))
        }
    }

    /**
     * Queue a sync operation
     */
    suspend fun <T : Any> queueSync(
        repositoryId: String,
        localDataSource: LocalDataSource<T>,
        remoteDataSource: RemoteDataSource<T>,
        priority: SyncPriority = SyncPriority.NORMAL,
        entities: List<T>? = null
    ): Result<String> {
        return try {
            val operationId = generateOperationId()
            val operation = SyncOperation(
                operationId = operationId,
                repositoryId = repositoryId,
                localDataSource = localDataSource as LocalDataSource<Any>,
                remoteDataSource = remoteDataSource as RemoteDataSource<Any>,
                priority = priority,
                entities = entities as? List<Any>,
                timestamp = System.currentTimeMillis()
            )

            syncQueue.send(operation)

            mutex.withLock {
                activeSyncs[operationId] = SyncStatus.QUEUED
            }

            _syncEvents.tryEmit(SyncEvent.SyncQueued(operationId, repositoryId, priority))
            Result.success(operationId)
        } catch (e: Exception) {
            Result.failure(RepositoryError.UnknownError(cause = e))
        }
    }

    /**
     * Perform immediate sync for critical operations
     */
    suspend fun <T : Any> syncImmediate(
        repositoryId: String,
        localDataSource: LocalDataSource<T>,
        remoteDataSource: RemoteDataSource<T>,
        entities: List<T>? = null
    ): Result<SyncResult<T>> {
        return try {
            val operationId = generateOperationId()
            mutex.withLock {
                activeSyncs[operationId] = SyncStatus.IN_PROGRESS
            }

            _syncEvents.tryEmit(SyncEvent.SyncStarted(operationId, repositoryId))

            val result = performSync(
                operationId = operationId,
                repositoryId = repositoryId,
                localDataSource = localDataSource as LocalDataSource<Any>,
                remoteDataSource = remoteDataSource as RemoteDataSource<Any>,
                entities = entities as? List<Any>
            )

            mutex.withLock {
                activeSyncs.remove(operationId)
            }

            @Suppress("UNCHECKED_CAST")
            Result.success(result.getOrThrow() as SyncResult<T>)
        } catch (e: Exception) {
            Result.failure(e as? RepositoryError ?: RepositoryError.UnknownError(cause = e))
        }
    }

    /**
     * Get sync status for an operation
     */
    suspend fun getSyncStatus(operationId: String): SyncStatus? {
        return mutex.withLock {
            activeSyncs[operationId]
        }
    }

    /**
     * Cancel a queued sync operation
     */
    suspend fun cancelSync(operationId: String): Result<Unit> {
        return try {
            mutex.withLock {
                val status = activeSyncs[operationId]
                if (status == SyncStatus.QUEUED) {
                    activeSyncs[operationId] = SyncStatus.CANCELLED
                    _syncEvents.tryEmit(SyncEvent.SyncCancelled(operationId))
                    Result.success(Unit)
                } else {
                    Result.failure(RepositoryError.InvalidState(
                        "Cannot cancel sync operation in status: $status"
                    ))
                }
            }
        } catch (e: Exception) {
            Result.failure(RepositoryError.UnknownError(cause = e))
        }
    }

    /**
     * Get current sync statistics
     */
    suspend fun getSyncStatistics(): SyncStatistics {
        return mutex.withLock {
            syncStatistics
        }
    }

    /**
     * Get active sync operations
     */
    suspend fun getActiveSyncs(): Map<String, SyncStatus> {
        return mutex.withLock {
            activeSyncs.toMap()
        }
    }

    /**
     * Start the background sync processor
     */
    private fun startSyncProcessor() {
        syncProcessor = coroutineScope.launch {
            while (isActive) {
                try {
                    val operation = syncQueue.receive()

                    // Check if operation was cancelled
                    val status = mutex.withLock { activeSyncs[operation.operationId] }
                    if (status == SyncStatus.CANCELLED) {
                        continue
                    }

                    // Process sync operation
                    launch {
                        processSyncOperation(operation)
                    }
                } catch (e: Exception) {
                    // Log error and continue processing
                }
            }
        }
    }

    /**
     * Process a single sync operation
     */
    private suspend fun processSyncOperation(operation: SyncOperation) {
        try {
            mutex.withLock {
                activeSyncs[operation.operationId] = SyncStatus.IN_PROGRESS
            }

            _syncEvents.tryEmit(SyncEvent.SyncStarted(operation.operationId, operation.repositoryId))

            val result = performSync(
                operationId = operation.operationId,
                repositoryId = operation.repositoryId,
                localDataSource = operation.localDataSource,
                remoteDataSource = operation.remoteDataSource,
                entities = operation.entities
            )

            if (result.isSuccess) {
                mutex.withLock {
                    activeSyncs[operation.operationId] = SyncStatus.COMPLETED
                    syncStatistics = syncStatistics.copy(
                        successful = syncStatistics.successful + 1
                    )
                }
                _syncEvents.tryEmit(SyncEvent.SyncCompleted(operation.operationId, operation.repositoryId))
            } else {
                mutex.withLock {
                    activeSyncs[operation.operationId] = SyncStatus.FAILED
                    syncStatistics = syncStatistics.copy(
                        failed = syncStatistics.failed + 1
                    )
                }
                _syncEvents.tryEmit(SyncEvent.SyncFailed(
                    operation.operationId,
                    operation.repositoryId,
                    result.exceptionOrNull() as? RepositoryError ?: RepositoryError.UnknownError()
                ))
            }

        } catch (e: Exception) {
            mutex.withLock {
                activeSyncs[operation.operationId] = SyncStatus.FAILED
                syncStatistics = syncStatistics.copy(
                    failed = syncStatistics.failed + 1
                )
            }
            _syncEvents.tryEmit(SyncEvent.SyncFailed(
                operation.operationId,
                operation.repositoryId,
                e as? RepositoryError ?: RepositoryError.UnknownError(cause = e)
            ))
        } finally {
            // Clean up completed/failed operations after a delay
            coroutineScope.launch {
                delay(60_000) // 1 minute cleanup delay
                mutex.withLock {
                    activeSyncs.remove(operation.operationId)
                }
            }
        }
    }

    /**
     * Perform the actual sync operation
     */
    private suspend fun performSync(
        operationId: String,
        repositoryId: String,
        localDataSource: LocalDataSource<Any>,
        remoteDataSource: RemoteDataSource<Any>,
        entities: List<Any>?
    ): Result<SyncResult<Any>> {
        return try {
            // Get entities to sync
            val entitiesToSync = entities ?: localDataSource.fetchAll().getOrThrow()

            // Perform remote sync
            val syncResult = remoteDataSource.sync(entitiesToSync).getOrThrow()

            // Handle conflicts
            val resolvedResult = if (syncResult.conflicts.isNotEmpty()) {
                resolveConflicts(repositoryId, syncResult)
            } else {
                syncResult
            }

            // Update local storage with synced entities
            if (resolvedResult.synced.isNotEmpty()) {
                localDataSource.saveAll(resolvedResult.synced).getOrThrow()
            }

            // Update statistics
            mutex.withLock {
                syncStatistics = syncStatistics.copy(
                    totalProcessed = syncStatistics.totalProcessed + entitiesToSync.size,
                    conflicts = syncStatistics.conflicts + resolvedResult.conflicts.size
                )
            }

            Result.success(resolvedResult)
        } catch (e: Exception) {
            Result.failure(e as? RepositoryError ?: RepositoryError.UnknownError(cause = e))
        }
    }

    /**
     * Resolve sync conflicts using configured resolution strategy
     */
    private suspend fun resolveConflicts(
        repositoryId: String,
        syncResult: SyncResult<Any>
    ): SyncResult<Any> {
        val conflictHandler = conflictResolutionHandlers[repositoryId]
        val resolvedConflicts = mutableListOf<SyncConflict<Any>>()
        val resolvedEntities = mutableListOf<Any>()

        for (conflict in syncResult.conflicts) {
            try {
                val resolution = conflictHandler?.let { handler ->
                    @Suppress("UNCHECKED_CAST")
                    (handler as ConflictResolutionHandler<Any>).resolve(conflict)
                } ?: resolveConflictWithStrategy(conflict, configuration.conflictResolution)

                when (resolution.action) {
                    ConflictResolutionAction.USE_LOCAL -> {
                        resolvedEntities.add(conflict.localEntity)
                    }
                    ConflictResolutionAction.USE_REMOTE -> {
                        resolvedEntities.add(conflict.remoteEntity)
                    }
                    ConflictResolutionAction.USE_MERGED -> {
                        resolution.mergedEntity?.let { resolvedEntities.add(it) }
                    }
                    ConflictResolutionAction.MANUAL -> {
                        resolvedConflicts.add(conflict)
                    }
                }
            } catch (e: Exception) {
                // If resolution fails, keep as unresolved conflict
                resolvedConflicts.add(conflict)
            }
        }

        return syncResult.copy(
            synced = syncResult.synced + resolvedEntities,
            conflicts = resolvedConflicts
        )
    }

    /**
     * Resolve conflict using automatic strategy
     */
    private fun resolveConflictWithStrategy(
        conflict: SyncConflict<Any>,
        strategy: ConflictResolution
    ): ConflictResolutionResult<Any> {
        return when (strategy) {
            ConflictResolution.LAST_WRITE_WINS -> {
                // This would need actual timestamp comparison
                ConflictResolutionResult(ConflictResolutionAction.USE_REMOTE, conflict.remoteEntity)
            }
            ConflictResolution.FIRST_WRITE_WINS -> {
                ConflictResolutionResult(ConflictResolutionAction.USE_LOCAL, conflict.localEntity)
            }
            ConflictResolution.LOCAL_WINS -> {
                ConflictResolutionResult(ConflictResolutionAction.USE_LOCAL, conflict.localEntity)
            }
            ConflictResolution.REMOTE_WINS -> {
                ConflictResolutionResult(ConflictResolutionAction.USE_REMOTE, conflict.remoteEntity)
            }
            ConflictResolution.MERGE -> {
                // Simple merge strategy - would need entity-specific implementation
                ConflictResolutionResult(ConflictResolutionAction.USE_REMOTE, conflict.remoteEntity)
            }
            ConflictResolution.MANUAL -> {
                ConflictResolutionResult(ConflictResolutionAction.MANUAL)
            }
        }
    }

    /**
     * Generate unique operation ID
     */
    private fun generateOperationId(): String {
        return "sync_${System.currentTimeMillis()}_${kotlin.random.Random.nextInt(1000, 9999)}"
    }

    /**
     * Shutdown the sync coordinator
     */
    suspend fun shutdown() {
        syncProcessor?.cancel()
        syncQueue.close()

        // Wait for active syncs to complete or timeout
        val timeout = 30_000L // 30 seconds
        val startTime = System.currentTimeMillis()

        while (System.currentTimeMillis() - startTime < timeout) {
            val activeCount = mutex.withLock {
                activeSyncs.values.count { it == SyncStatus.IN_PROGRESS }
            }
            if (activeCount == 0) break
            delay(100)
        }

        _syncEvents.tryEmit(SyncEvent.CoordinatorShutdown)
    }
}

/**
 * Sync operation data class
 */
private data class SyncOperation(
    val operationId: String,
    val repositoryId: String,
    val localDataSource: LocalDataSource<Any>,
    val remoteDataSource: RemoteDataSource<Any>,
    val priority: SyncPriority,
    val entities: List<Any>?,
    val timestamp: Long
)

/**
 * Sync status enum
 */
enum class SyncStatus {
    QUEUED, IN_PROGRESS, COMPLETED, FAILED, CANCELLED
}

/**
 * Sync events for monitoring
 */
sealed class SyncEvent {
    data class RepositoryRegistered(val repositoryId: String) : SyncEvent()
    data class SyncQueued(val operationId: String, val repositoryId: String, val priority: SyncPriority) : SyncEvent()
    data class SyncStarted(val operationId: String, val repositoryId: String) : SyncEvent()
    data class SyncCompleted(val operationId: String, val repositoryId: String) : SyncEvent()
    data class SyncFailed(val operationId: String, val repositoryId: String, val error: RepositoryError) : SyncEvent()
    data class SyncCancelled(val operationId: String) : SyncEvent()
    object CoordinatorShutdown : SyncEvent()
}

/**
 * Conflict resolution handler interface
 */
interface ConflictResolutionHandler<T : Any> {
    suspend fun resolve(conflict: SyncConflict<T>): ConflictResolutionResult<T>
}

/**
 * Conflict resolution result
 */
data class ConflictResolutionResult<T : Any>(
    val action: ConflictResolutionAction,
    val mergedEntity: T? = null
)

/**
 * Conflict resolution actions
 */
enum class ConflictResolutionAction {
    USE_LOCAL, USE_REMOTE, USE_MERGED, MANUAL
}


/**
 * Factory function to create sync coordinator
 */
fun createSyncCoordinator(
    configuration: SyncConfiguration = SyncConfiguration(),
    coroutineScope: CoroutineScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
): SyncCoordinator {
    return SyncCoordinator(configuration, coroutineScope)
}
