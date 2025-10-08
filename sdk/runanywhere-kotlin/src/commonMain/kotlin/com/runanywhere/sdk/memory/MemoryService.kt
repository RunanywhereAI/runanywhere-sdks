package com.runanywhere.sdk.memory

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Central memory management service
 * Manages model memory allocation, pressure handling, and cache eviction
 */
class MemoryService(
    private val allocationManager: AllocationManager = AllocationManager(),
    private val pressureHandler: PressureHandler = PressureHandler(),
    private val cacheEviction: CacheEviction = CacheEviction(),
    private val memoryMonitor: MemoryMonitor = MemoryMonitor()
) : MemoryManager {

    private val logger = SDKLogger("MemoryService")
    private val mutex = Mutex()

    // Memory thresholds
    private var memoryThreshold: Long = 500_000_000L // 500MB
    private var criticalThreshold: Long = 200_000_000L // 200MB

    init {
        setupIntegration()
    }

    private fun setupIntegration() {
        // Setup memory monitoring and pressure handling
        logger.info("Memory service initialized with threshold: ${memoryThreshold / 1_000_000}MB")
    }

    // MARK: - Model Memory Management

    suspend fun registerModel(
        model: MemoryLoadedModel,
        size: Long,
        service: Any, // TODO: Replace with LLMService when available
        priority: MemoryPriority = MemoryPriority.NORMAL
    ) {
        mutex.withLock {
            allocationManager.registerModel(model, size, service, priority)
        }

        // Check for memory pressure after registration
        checkMemoryConditions()
    }

    suspend fun unregisterModelFromMemory(modelId: String) {
        mutex.withLock {
            allocationManager.unregisterModel(modelId)
        }
    }

    fun touchModel(modelId: String) {
        allocationManager.touchModel(modelId)
    }

    // MARK: - Memory Pressure Management

    suspend fun handleMemoryPressure(level: MemoryPressureLevel = MemoryPressureLevel.WARNING) {
        logger.info("Handling memory pressure at level: $level")

        val targetMemory = calculateTargetMemory(level)
        val modelsToEvict = cacheEviction.selectModelsToEvict(targetMemory)

        pressureHandler.handlePressure(level, modelsToEvict)
    }

    suspend fun requestMemory(size: Long, priority: MemoryPriority = MemoryPriority.NORMAL): Boolean {
        return allocationManager.requestMemory(size, priority)
    }

    suspend fun releaseMemory(size: Long) {
        allocationManager.releaseMemory(size)
    }

    // MARK: - MemoryManager Protocol Implementation

    override fun getCurrentMemoryUsage(): Long {
        return allocationManager.getTotalModelMemory()
    }

    override fun getAvailableMemory(): Long {
        return memoryMonitor.getAvailableMemory()
    }

    override fun hasAvailableMemory(size: Long): Boolean {
        return getAvailableMemory() >= size
    }

    override suspend fun canAllocate(size: Long): Boolean {
        return requestMemory(size)
    }

    override suspend fun handleMemoryPressure() {
        handleMemoryPressure(MemoryPressureLevel.WARNING)
    }

    override fun setMemoryThreshold(threshold: Long) {
        this.memoryThreshold = threshold
    }

    override fun getLoadedModels(): List<LoadedModel> {
        return allocationManager.getLoadedModels()
    }

    override fun isHealthy(): Boolean {
        // Basic health check - ensure all components are available
        return memoryMonitor.getAvailableMemory() > 0
    }

    override suspend fun registerLoadedModel(modelId: String, size: Long, service: Any) {
        val memoryModel = MemoryLoadedModel(
            id = modelId,
            name = modelId,
            size = size,
            framework = "llama.cpp"
        )
        registerModel(memoryModel, size, service, MemoryPriority.NORMAL)
    }

    override suspend fun unregisterModel(modelId: String) {
        unregisterModelFromMemory(modelId)
    }

    // MARK: - Memory Information

    fun getMemoryStatistics(): MemoryStatistics {
        val totalMemory = memoryMonitor.getTotalMemory()
        val availableMemory = memoryMonitor.getAvailableMemory()
        val modelMemory = allocationManager.getTotalModelMemory()
        val loadedModelCount = allocationManager.getLoadedModelCount()
        val memoryPressure = availableMemory < memoryThreshold

        return MemoryStatistics(
            totalMemory = totalMemory,
            availableMemory = availableMemory,
            modelMemory = modelMemory,
            loadedModelCount = loadedModelCount,
            memoryPressure = memoryPressure
        )
    }

    // MARK: - Private Helpers

    private fun calculateTargetMemory(level: MemoryPressureLevel): Long {
        return when (level) {
            MemoryPressureLevel.NORMAL -> memoryThreshold
            MemoryPressureLevel.WARNING -> memoryThreshold / 2
            MemoryPressureLevel.CRITICAL -> criticalThreshold
            MemoryPressureLevel.URGENT -> criticalThreshold / 2
        }
    }

    private suspend fun checkMemoryConditions() {
        val available = getAvailableMemory()
        when {
            available < criticalThreshold / 2 -> {
                handleMemoryPressure(MemoryPressureLevel.URGENT)
            }
            available < criticalThreshold -> {
                handleMemoryPressure(MemoryPressureLevel.CRITICAL)
            }
            available < memoryThreshold -> {
                handleMemoryPressure(MemoryPressureLevel.WARNING)
            }
        }
    }
}

// MARK: - Memory Manager Interface

/**
 * Protocol for memory management
 */
interface MemoryManager {
    fun getCurrentMemoryUsage(): Long
    fun getAvailableMemory(): Long
    fun hasAvailableMemory(size: Long): Boolean
    suspend fun canAllocate(size: Long): Boolean
    suspend fun handleMemoryPressure()
    fun setMemoryThreshold(threshold: Long)
    fun getLoadedModels(): List<LoadedModel>
    fun isHealthy(): Boolean
    
    // Methods required by ModelLoadingService - EXACT copy of iOS MemoryManager
    suspend fun registerLoadedModel(modelId: String, size: Long, service: Any)
    suspend fun unregisterModel(modelId: String)
}

// MARK: - Memory Models

/**
 * Memory pressure levels
 */
enum class MemoryPressureLevel {
    NORMAL,
    WARNING,
    CRITICAL,
    URGENT
}

/**
 * Memory priority for allocation
 */
enum class MemoryPriority {
    LOW,
    NORMAL,
    HIGH,
    CRITICAL
}

/**
 * Loaded model representation for memory tracking
 */
data class MemoryLoadedModel(
    val id: String,
    val name: String,
    val size: Long,
    val framework: String,
    var lastAccessed: Long = System.currentTimeMillis()
)

/**
 * Loaded model with service
 */
data class LoadedModel(
    val model: MemoryLoadedModel,
    val service: Any // TODO: Replace with LLMService
)

/**
 * Memory statistics
 */
data class MemoryStatistics(
    val totalMemory: Long,
    val availableMemory: Long,
    val modelMemory: Long,
    val loadedModelCount: Int,
    val memoryPressure: Boolean
)
