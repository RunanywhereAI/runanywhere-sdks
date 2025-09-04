package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * Repository for managing model information - exact match with iOS
 */
class ModelInfoRepositoryImpl : ModelInfoRepository {

    // In-memory storage for development (replace with actual database in production)
    private val models = mutableMapOf<String, ModelInfo>()
    private val mutex = Mutex()

    override suspend fun save(entity: ModelInfo) {
        mutex.withLock {
            entity.updatedAt = Clock.System.now()
            models[entity.id] = entity
        }
    }

    override suspend fun fetch(id: String): ModelInfo? {
        return mutex.withLock {
            models[id]
        }
    }

    override suspend fun fetchAll(): List<ModelInfo> {
        return mutex.withLock {
            models.values.toList()
        }
    }

    override suspend fun delete(id: String) {
        mutex.withLock {
            models.remove(id)
        }
    }

    override suspend fun fetchByFramework(framework: LLMFramework): List<ModelInfo> {
        return mutex.withLock {
            models.values.filter { model ->
                model.compatibleFrameworks.contains(framework)
            }
        }
    }

    override suspend fun fetchByCategory(category: ModelCategory): List<ModelInfo> {
        return mutex.withLock {
            models.values.filter { it.category == category }
        }
    }

    override suspend fun fetchDownloaded(): List<ModelInfo> {
        return mutex.withLock {
            models.values.filter { it.isDownloaded }
        }
    }

    override suspend fun updateDownloadStatus(modelId: String, localPath: String?) {
        mutex.withLock {
            models[modelId]?.let { model ->
                model.localPath = localPath
                model.updatedAt = Clock.System.now()
            }
        }
    }

    override suspend fun updateLastUsed(modelId: String) {
        mutex.withLock {
            models[modelId]?.let { model ->
                model.lastUsed = Clock.System.now()
                model.usageCount++
                model.updatedAt = Clock.System.now()
            }
        }
    }

    override suspend fun fetchPendingSync(): List<ModelInfo> {
        return mutex.withLock {
            models.values.filter { it.syncPending }
        }
    }

    override suspend fun markSynced(ids: List<String>) {
        mutex.withLock {
            ids.forEach { id ->
                models[id]?.let { model ->
                    model.syncPending = false
                    model.updatedAt = Clock.System.now()
                }
            }
        }
    }
}
