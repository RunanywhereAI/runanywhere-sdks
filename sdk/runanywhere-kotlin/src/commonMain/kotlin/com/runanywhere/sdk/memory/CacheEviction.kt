package com.runanywhere.sdk.memory

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Cache eviction strategy for model memory management
 * Implements LRU (Least Recently Used) with priority awareness
 */
class CacheEviction {
    private val logger = SDKLogger("CacheEviction")
    private val allocationManager = AllocationManager()

    /**
     * Select models to evict based on target memory to free
     */
    fun selectModelsToEvict(targetMemory: Long): List<String> {
        logger.debug("Selecting models to evict to free ${targetMemory / 1_000_000}MB")

        return allocationManager.getModelsForEviction(targetMemory)
    }

    /**
     * Eviction strategies
     */
    enum class EvictionStrategy {
        LRU, // Least Recently Used
        LFU, // Least Frequently Used
        FIFO, // First In First Out
        PRIORITY, // Priority-based
    }

    /**
     * Apply eviction strategy to select models
     */
    fun selectModelsWithStrategy(
        targetMemory: Long,
        strategy: EvictionStrategy = EvictionStrategy.LRU,
    ): List<String> {
        logger.debug("Using $strategy strategy to select models for eviction")

        return when (strategy) {
            EvictionStrategy.LRU -> selectLRUModels(targetMemory)
            EvictionStrategy.LFU -> selectLFUModels(targetMemory)
            EvictionStrategy.FIFO -> selectFIFOModels(targetMemory)
            EvictionStrategy.PRIORITY -> selectPriorityModels(targetMemory)
        }
    }

    private fun selectLRUModels(targetMemory: Long): List<String> {
        // LRU is the default implementation in AllocationManager
        return allocationManager.getModelsForEviction(targetMemory)
    }

    private fun selectLFUModels(targetMemory: Long): List<String> {
        // TODO: Implement LFU strategy (requires frequency tracking)
        logger.warning("LFU strategy not yet implemented, falling back to LRU")
        return selectLRUModels(targetMemory)
    }

    private fun selectFIFOModels(targetMemory: Long): List<String> {
        // TODO: Implement FIFO strategy (requires creation time tracking)
        logger.warning("FIFO strategy not yet implemented, falling back to LRU")
        return selectLRUModels(targetMemory)
    }

    private fun selectPriorityModels(targetMemory: Long): List<String> {
        // Priority-based is already incorporated in the default implementation
        return allocationManager.getModelsForEviction(targetMemory)
    }
}
