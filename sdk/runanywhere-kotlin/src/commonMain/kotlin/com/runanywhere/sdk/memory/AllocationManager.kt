package com.runanywhere.sdk.memory

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Manages memory allocation for models
 * Tracks loaded models and their memory usage
 */
class AllocationManager {

    private val models = mutableMapOf<String, ModelMemoryInfo>()
    private val mutex = Mutex()
    private var totalAllocated: Long = 0L

    data class ModelMemoryInfo(
        val model: MemoryLoadedModel,
        val size: Long,
        val service: Any,
        val priority: MemoryPriority,
        var lastAccessed: Long = System.currentTimeMillis()
    )

    suspend fun registerModel(
        model: MemoryLoadedModel,
        size: Long,
        service: Any,
        priority: MemoryPriority
    ) {
        mutex.withLock {
            models[model.id] = ModelMemoryInfo(model, size, service, priority)
            totalAllocated += size
        }
    }

    suspend fun unregisterModel(modelId: String) {
        mutex.withLock {
            models.remove(modelId)?.let { info ->
                totalAllocated -= info.size
            }
        }
    }

    fun touchModel(modelId: String) {
        models[modelId]?.let { info ->
            info.lastAccessed = System.currentTimeMillis()
            info.model.lastAccessed = System.currentTimeMillis()
        }
    }

    suspend fun requestMemory(size: Long, priority: MemoryPriority): Boolean {
        mutex.withLock {
            // Simple allocation check - can be enhanced with eviction logic
            val memoryMonitor = MemoryMonitor()
            val available = memoryMonitor.getAvailableMemory()

            return when {
                available >= size -> {
                    totalAllocated += size
                    true
                }
                priority == MemoryPriority.CRITICAL -> {
                    // For critical priority, we might evict other models
                    // TODO: Implement eviction logic
                    true
                }
                else -> false
            }
        }
    }

    suspend fun releaseMemory(size: Long) {
        mutex.withLock {
            totalAllocated = maxOf(0, totalAllocated - size)
        }
    }

    fun getTotalModelMemory(): Long = totalAllocated

    fun getLoadedModelCount(): Int = models.size

    fun getLoadedModels(): List<LoadedModel> {
        return models.values.map { info ->
            LoadedModel(model = info.model, service = info.service)
        }
    }

    fun getModelsForEviction(targetSize: Long): List<String> {
        // Sort by priority and last accessed time
        val sortedModels = models.entries
            .sortedWith(compareBy(
                { it.value.priority.ordinal },
                { it.value.lastAccessed }
            ))

        val modelsToEvict = mutableListOf<String>()
        var freedMemory = 0L

        for (entry in sortedModels) {
            if (freedMemory >= targetSize) break
            modelsToEvict.add(entry.key)
            freedMemory += entry.value.size
        }

        return modelsToEvict
    }
}
