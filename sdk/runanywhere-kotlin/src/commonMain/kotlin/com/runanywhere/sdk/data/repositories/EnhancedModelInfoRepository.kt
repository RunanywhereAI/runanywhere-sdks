package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.config.*
import com.runanywhere.sdk.data.sources.*
import com.runanywhere.sdk.data.sync.SyncCoordinator
import com.runanywhere.sdk.data.sync.ConflictResolutionHandler
import com.runanywhere.sdk.data.sync.ConflictResolutionResult
import com.runanywhere.sdk.data.sync.ConflictResolutionAction
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.serializer
import kotlinx.coroutines.CoroutineScope
import kotlin.time.Duration.Companion.days
import com.runanywhere.sdk.utils.toSimpleInstant

/**
 * Enhanced ModelInfo repository using the new repository architecture.
 * Provides comprehensive model information management with caching, sync, and conflict resolution.
 */
class EnhancedModelInfoRepository(
    localDataSource: LocalDataSource<ModelInfo>? = null,
    remoteDataSource: RemoteDataSource<ModelInfo>? = null,
    syncCoordinator: SyncCoordinator? = null,
    configuration: RepositoryConfiguration = RepositoryConfiguration.default,
    coroutineScope: CoroutineScope
) : BaseRepository<ModelInfo>(
    repositoryId = "ModelInfoRepository",
    localDataSource = localDataSource ?: createDefaultLocalDataSource(),
    remoteDataSource = remoteDataSource,
    syncCoordinator = syncCoordinator,
    configuration = configuration,
    coroutineScope = coroutineScope
) {

    // Custom conflict resolution handler for ModelInfo
    override val conflictResolutionHandler = object : ConflictResolutionHandler<ModelInfo> {
        override suspend fun resolve(conflict: SyncConflict<ModelInfo>): ConflictResolutionResult<ModelInfo> {
            val local = conflict.localEntity
            val remote = conflict.remoteEntity

            // Custom merge logic for ModelInfo
            return when (conflict.conflictType) {
                ConflictType.MODIFICATION_CONFLICT -> {
                    // Merge based on most recent update and usage information
                    val merged = mergeModelInfo(local, remote)
                    ConflictResolutionResult(ConflictResolutionAction.USE_MERGED, merged)
                }
                ConflictType.VERSION_CONFLICT -> {
                    // Use the version with higher usage count or more recent update
                    if (local.usageCount > remote.usageCount) {
                        ConflictResolutionResult(ConflictResolutionAction.USE_LOCAL, local)
                    } else {
                        ConflictResolutionResult(ConflictResolutionAction.USE_REMOTE, remote)
                    }
                }
                else -> ConflictResolutionResult(ConflictResolutionAction.USE_REMOTE, remote)
            }
        }
    }

    // Enhanced ModelInfoRepository functionality (no longer implementing ModelInfoRepository interface)
    // These methods provide similar functionality but with Result types from BaseRepository

    suspend fun fetchByFramework(framework: LLMFramework): List<ModelInfo> {
        return super.fetchAll().getOrElse { emptyList() }.filter { model ->
            model.compatibleFrameworks.contains(framework)
        }
    }

    suspend fun fetchByCategory(category: ModelCategory): List<ModelInfo> {
        return super.fetchAll().getOrElse { emptyList() }.filter { it.category == category }
    }

    suspend fun fetchDownloaded(): List<ModelInfo> {
        return super.fetchAll().getOrElse { emptyList() }.filter { it.isDownloaded }
    }

    suspend fun updateDownloadStatus(modelId: String, localPath: String?) {
        val model = fetchById(modelId).getOrNull()
        if (model != null) {
            val updatedModel = model.copy(
                localPath = localPath,
                updatedAt = com.runanywhere.sdk.utils.SimpleInstant.now()
            )
            save(updatedModel).getOrThrow()
        }
    }

    suspend fun updateLastUsed(modelId: String) {
        val model = fetchById(modelId).getOrNull()
        if (model != null) {
            val updatedModel = model.copy(
                lastUsed = com.runanywhere.sdk.utils.SimpleInstant.now(),
                usageCount = model.usageCount + 1,
                updatedAt = com.runanywhere.sdk.utils.SimpleInstant.now()
            )
            save(updatedModel).getOrThrow()
        }
    }

    suspend fun fetchPendingSync(): List<ModelInfo> {
        return super.fetchAll().getOrElse { emptyList() }.filter { it.syncPending }
    }

    suspend fun markSynced(ids: List<String>) {
        ids.forEach { id ->
            val model = fetchById(id).getOrNull()
            if (model != null) {
                val updatedModel = model.copy(
                    syncPending = false,
                    updatedAt = com.runanywhere.sdk.utils.SimpleInstant.now()
                )
                save(updatedModel).getOrThrow()
            }
        }
    }

    // Enhanced functionality beyond the original interface

    /**
     * Observe models by framework
     */
    fun observeByFramework(framework: LLMFramework): Flow<List<ModelInfo>> {
        return observeAll().map { models ->
            models.filter { model ->
                model.compatibleFrameworks.contains(framework)
            }
        }
    }

    /**
     * Observe models by category
     */
    fun observeByCategory(category: ModelCategory): Flow<List<ModelInfo>> {
        return observeAll().map { models ->
            models.filter { it.category == category }
        }
    }

    /**
     * Observe downloaded models
     */
    fun observeDownloaded(): Flow<List<ModelInfo>> {
        return observeAll().map { models ->
            models.filter { it.isDownloaded }
        }
    }

    /**
     * Search models by name or metadata
     */
    suspend fun searchModels(query: String): List<ModelInfo> {
        return super.fetchAll().getOrElse { emptyList() }.filter { model ->
            model.name.contains(query, ignoreCase = true) ||
            model.metadata?.description?.contains(query, ignoreCase = true) == true ||
            model.metadata?.tags?.any { it.contains(query, ignoreCase = true) } == true
        }
    }

    /**
     * Get models compatible with specific requirements
     */
    suspend fun getCompatibleModels(
        framework: LLMFramework? = null,
        category: ModelCategory? = null,
        maxMemoryRequired: Long? = null,
        minContextLength: Int? = null
    ): List<ModelInfo> {
        return super.fetchAll().getOrElse { emptyList() }.filter { model ->
            (framework == null || model.compatibleFrameworks.contains(framework)) &&
            (category == null || model.category == category) &&
            (maxMemoryRequired == null || (model.memoryRequired ?: 0) <= maxMemoryRequired) &&
            (minContextLength == null || (model.effectiveContextLength ?: 0) >= minContextLength)
        }
    }

    /**
     * Get usage statistics for models
     */
    suspend fun getUsageStatistics(): Map<String, ModelUsageStats> {
        return super.fetchAll().getOrElse { emptyList() }.associate { model ->
            model.id to ModelUsageStats(
                modelId = model.id,
                usageCount = model.usageCount,
                lastUsed = model.lastUsed?.toEpochMilliseconds() ?: 0,
                isDownloaded = model.isDownloaded,
                memoryRequired = model.memoryRequired ?: 0,
                downloadSize = model.downloadSize ?: 0
            )
        }
    }

    /**
     * Custom merge logic for ModelInfo conflicts
     */
    private fun mergeModelInfo(local: ModelInfo, remote: ModelInfo): ModelInfo {
        // Merge strategy: prioritize local runtime data, remote metadata updates
        return remote.copy(
            // Keep local runtime state
            localPath = local.localPath,
            lastUsed = maxOf(local.lastUsed?.toEpochMilliseconds() ?: 0, remote.lastUsed?.toEpochMilliseconds() ?: 0)
                .let { if (it > 0) it.toSimpleInstant() else null },
            usageCount = maxOf(local.usageCount, remote.usageCount),

            // Update timestamp to most recent
            updatedAt = com.runanywhere.sdk.utils.SimpleInstant.now(),

            // Preserve sync state from local
            syncPending = local.syncPending || remote.syncPending
        )
    }

    /**
     * Override initialization to set up model-specific behavior
     */
    override suspend fun onInitialize() {
        super.onInitialize()

        // Pre-load essential models if needed
        if (configuration.cache.preloadStrategy == PreloadStrategy.EAGER) {
            // Could implement preloading logic here
        }
    }

    companion object {
        /**
         * Create default local data source for ModelInfo
         */
        fun createDefaultLocalDataSource(): LocalDataSource<ModelInfo> {
            return createHighPerformanceLocalDataSource(
                entityName = "ModelInfo",
                serializer = serializer<ModelInfo>()
            )
        }

        /**
         * Create ModelInfo repository with high performance configuration
         */
        fun createHighPerformance(
            baseUrl: String? = null,
            apiKeyProvider: (() -> String?)? = null,
            syncCoordinator: SyncCoordinator? = null,
            coroutineScope: CoroutineScope
        ): EnhancedModelInfoRepository {
            val localDataSource = createDefaultLocalDataSource()

            val remoteDataSource = if (baseUrl != null) {
                createHighThroughputRemoteDataSource(
                    baseUrl = baseUrl,
                    entityName = "ModelInfo",
                    serializer = serializer<ModelInfo>(),
                    apiKeyProvider = apiKeyProvider ?: { null }
                )
            } else null

            return EnhancedModelInfoRepository(
                localDataSource = localDataSource,
                remoteDataSource = remoteDataSource,
                syncCoordinator = syncCoordinator,
                configuration = RepositoryConfiguration.highPerformance,
                coroutineScope = coroutineScope
            )
        }

        /**
         * Create ModelInfo repository for offline-first scenarios
         */
        fun createOfflineFirst(
            baseUrl: String? = null,
            apiKeyProvider: (() -> String?)? = null,
            syncCoordinator: SyncCoordinator? = null,
            coroutineScope: CoroutineScope
        ): EnhancedModelInfoRepository {
            val localDataSource = CacheLocalDataSource(
                cacheConfiguration = CacheConfiguration(
                    maxSize = 1000,
                    ttl = 7.days, // Keep models cached longer
                    evictionPolicy = EvictionPolicy.LFU // Keep frequently used models
                ),
                entityName = "ModelInfo",
                serializer = serializer<ModelInfo>()
            )

            val remoteDataSource = if (baseUrl != null) {
                createRobustRemoteDataSource(
                    baseUrl = baseUrl,
                    entityName = "ModelInfo",
                    serializer = serializer<ModelInfo>(),
                    apiKeyProvider = apiKeyProvider ?: { null }
                )
            } else null

            return EnhancedModelInfoRepository(
                localDataSource = localDataSource,
                remoteDataSource = remoteDataSource,
                syncCoordinator = syncCoordinator,
                configuration = RepositoryConfiguration.offlineFirst,
                coroutineScope = coroutineScope
            )
        }
    }
}

/**
 * Model usage statistics data class
 */
data class ModelUsageStats(
    val modelId: String,
    val usageCount: Int,
    val lastUsed: Long,
    val isDownloaded: Boolean,
    val memoryRequired: Long,
    val downloadSize: Long
)
