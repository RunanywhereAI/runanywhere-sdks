package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.utils.SimpleInstant
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Common implementation of ModelInfoRepository
 * Uses in-memory storage - can be extended with platform-specific persistence later
 */
class ModelInfoRepositoryImpl : ModelInfoRepository {

    // In-memory storage (can be backed by PlatformStorage in the future)
    private val models = mutableMapOf<String, ModelInfo>()
    private val mutex = Mutex()
    private val logger = com.runanywhere.sdk.foundation.SDKLogger("ModelInfoRepositoryImpl")

    override suspend fun save(entity: ModelInfo) {
        mutex.withLock {
            entity.updatedAt = SimpleInstant.now()
            models[entity.id] = entity
            logger.debug("Saved model: ${entity.id}, localPath: ${entity.localPath}")
        }
    }

    /**
     * Scan file system to find downloaded models and update localPath
     * This is called on startup to restore download state from disk
     */
    suspend fun scanAndUpdateDownloadedModels(baseModelsPath: String, fileSystem: com.runanywhere.sdk.storage.FileSystem) {
        mutex.withLock {
            logger.info("🔍 Scanning for downloaded models in: $baseModelsPath")
            var foundCount = 0

            models.values.forEach { model ->
                // Skip if already has localPath
                if (model.localPath != null) {
                    logger.debug("Model ${model.id} already has localPath: ${model.localPath}")
                    return@forEach
                }

                // Build expected path based on framework
                val framework = model.preferredFramework ?: model.compatibleFrameworks.firstOrNull()
                if (framework != null) {
                    // Try multiple path variations to ensure compatibility
                    val pathVariations = listOf(
                        "$baseModelsPath/${framework.value}/${model.id}/${model.id}.${model.format.value}",  // CamelCase: LlamaCpp
                        "$baseModelsPath/llama_cpp/${model.id}/${model.id}.${model.format.value}",          // snake_case for llama.cpp
                        "$baseModelsPath/${framework.value.lowercase()}/${model.id}/${model.id}.${model.format.value}" // lowercase
                    )

                    for (expectedPath in pathVariations) {
                        logger.debug("Checking path for ${model.id}: $expectedPath")

                        // Check if file exists using FileSystem
                        if (fileSystem.existsSync(expectedPath)) {
                            // File found! Update model with localPath
                            model.localPath = expectedPath
                            model.updatedAt = SimpleInstant.now()
                            foundCount++
                            logger.info("✅ Found downloaded model: ${model.name} at $expectedPath")
                            return@forEach // Stop checking other paths for this model
                        }
                    }

                    logger.debug("Model file not found for ${model.id} in any expected location")
                }
            }

            logger.info("✅ Scan complete. Found $foundCount downloaded models")
        }
    }

    override suspend fun fetch(id: String): ModelInfo? {
        return mutex.withLock {
            models[id]
        }
    }

    override suspend fun fetchAll(): List<ModelInfo> {
        return mutex.withLock {
            val allModels = models.values.toList()
            logger.debug("Fetching all models. Count: ${allModels.size}")
            allModels.forEach { model ->
                logger.debug("  - ${model.name}: localPath=${model.localPath}, isDownloaded=${model.isDownloaded}")
            }
            allModels
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
                model.updatedAt = SimpleInstant.now()
            }
        }
    }

    override suspend fun updateLastUsed(modelId: String) {
        mutex.withLock {
            models[modelId]?.let { model ->
                model.lastUsed = SimpleInstant.now()
                model.usageCount++
                model.updatedAt = SimpleInstant.now()
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
                    model.updatedAt = SimpleInstant.now()
                }
            }
        }
    }
}
