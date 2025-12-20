package com.runanywhere.sdk.memory

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Memory monitoring component
 * Platform-specific implementations will provide actual memory statistics
 */
expect class MemoryMonitor() {
    fun getTotalMemory(): Long

    fun getAvailableMemory(): Long

    fun getUsedMemory(): Long
}

/**
 * Common memory monitoring utilities
 */
object MemoryMonitorUtils {
    private val logger = SDKLogger("MemoryMonitor")

    fun logMemoryStatus(
        total: Long,
        available: Long,
        used: Long,
    ) {
        val totalMB = total / 1_000_000
        val availableMB = available / 1_000_000
        val usedMB = used / 1_000_000
        val usagePercent = if (total > 0) (used * 100) / total else 0

        logger.debug("Memory Status - Total: ${totalMB}MB, Available: ${availableMB}MB, Used: ${usedMB}MB ($usagePercent%)")
    }

    fun isMemoryPressureHigh(
        available: Long,
        threshold: Long = 200_000_000L,
    ): Boolean = available < threshold
}
