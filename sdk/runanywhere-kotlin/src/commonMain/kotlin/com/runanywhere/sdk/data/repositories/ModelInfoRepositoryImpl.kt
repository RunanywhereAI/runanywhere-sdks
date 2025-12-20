package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
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
    private val logger =
        com.runanywhere.sdk.foundation
            .SDKLogger("ModelInfoRepositoryImpl")

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
     * Matches iOS RegistryService behavior of discovering models on disk
     *
     * Uses registered ModelStorageStrategy from each framework adapter
     * to detect framework-specific model structures.
     */
    suspend fun scanAndUpdateDownloadedModels(
        baseModelsPath: String,
        fileSystem: com.runanywhere.sdk.storage.FileSystem,
    ) {
        mutex.withLock {
            logger.info("🔍 Scanning for downloaded models in: $baseModelsPath")
            var foundCount = 0

            models.values.forEach { model ->
                // Skip if already has valid localPath that exists
                if (model.localPath != null && fileSystem.existsSync(model.localPath!!)) {
                    logger.debug("Model ${model.id} already has valid localPath: ${model.localPath}")
                    return@forEach
                }

                // Build expected path based on framework
                // IMPORTANT: Use framework.value to match iOS's framework.rawValue exactly
                // iOS folder pattern: Models/{framework.rawValue}/{modelId}/ e.g., Models/LlamaCpp/liquid-ai-4b/
                val framework = model.preferredFramework ?: model.compatibleFrameworks.firstOrNull()
                if (framework != null) {
                    // Try framework-specific storage strategy first (e.g., ONNX, LlamaCpp)
                    val storageStrategy = ModuleRegistry.getStorageStrategy(framework)
                    // Use framework.value (matches iOS rawValue) - e.g., "LlamaCpp", "ONNX"
                    val modelDir = "$baseModelsPath/${framework.value}/${model.id}"

                    if (storageStrategy != null) {
                        logger.debug("Using ${framework.name} storage strategy for ${model.id}")

                        // Use framework's strategy to find the model
                        val foundPath = storageStrategy.findModelPath(model.id, modelDir)
                        if (foundPath != null) {
                            model.localPath = foundPath
                            model.updatedAt = SimpleInstant.now()
                            foundCount++
                            logger.info("✅ Found ${framework.name} model: ${model.name} at $foundPath")
                            return@forEach
                        }
                    }

                    // Fallback: Check standard path patterns for frameworks without storage strategy
                    // Use framework.value to match iOS pattern exactly
                    val pathVariations =
                        listOf(
                            // Primary pattern matching iOS: Models/{framework.rawValue}/{modelId}/{filename}
                            "$baseModelsPath/${framework.value}/${model.id}/${model.id}.${model.format.value}",
                            // Also check for directory-based models (ONNX)
                            "$baseModelsPath/${framework.value}/${model.id}",
                        )

                    for (expectedPath in pathVariations) {
                        logger.debug("Checking path for ${model.id}: $expectedPath")

                        if (fileSystem.existsSync(expectedPath) && !fileSystem.isDirectorySync(expectedPath)) {
                            model.localPath = expectedPath
                            model.updatedAt = SimpleInstant.now()
                            foundCount++
                            logger.info("✅ Found downloaded model: ${model.name} at $expectedPath")
                            return@forEach
                        }
                    }

                    logger.debug("Model file not found for ${model.id} in any expected location")
                }
            }

            logger.info("✅ Scan complete. Found $foundCount downloaded models")
        }
    }

    override suspend fun fetch(id: String): ModelInfo? =
        mutex.withLock {
            models[id]
        }

    override suspend fun fetchAll(): List<ModelInfo> =
        mutex.withLock {
            val allModels = models.values.toList()
            logger.debug("Fetching all models. Count: ${allModels.size}")
            allModels.forEach { model ->
                logger.debug("  - ${model.name}: localPath=${model.localPath}, isDownloaded=${model.isDownloaded}")
            }
            allModels
        }

    override suspend fun delete(id: String) {
        mutex.withLock {
            models.remove(id)
        }
    }

    override suspend fun fetchByFramework(framework: InferenceFramework): List<ModelInfo> =
        mutex.withLock {
            models.values.filter { model ->
                model.compatibleFrameworks.contains(framework)
            }
        }

    override suspend fun fetchByCategory(category: ModelCategory): List<ModelInfo> =
        mutex.withLock {
            models.values.filter { it.category == category }
        }

    override suspend fun fetchDownloaded(): List<ModelInfo> =
        mutex.withLock {
            models.values.filter { it.isDownloaded }
        }

    override suspend fun updateDownloadStatus(
        modelId: String,
        localPath: String?,
    ) {
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

    override suspend fun fetchPendingSync(): List<ModelInfo> =
        mutex.withLock {
            models.values.filter { it.syncPending }
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
