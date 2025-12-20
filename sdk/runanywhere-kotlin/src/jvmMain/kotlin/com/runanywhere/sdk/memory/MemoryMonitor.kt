package com.runanywhere.sdk.memory

/**
 * JVM implementation of memory monitoring
 */
actual class MemoryMonitor {
    private val runtime = Runtime.getRuntime()

    actual fun getTotalMemory(): Long = runtime.maxMemory()

    actual fun getAvailableMemory(): Long {
        val maxMemory = runtime.maxMemory()
        val totalMemory = runtime.totalMemory()
        val freeMemory = runtime.freeMemory()

        // Available = free memory + (max - total)
        return freeMemory + (maxMemory - totalMemory)
    }

    actual fun getUsedMemory(): Long = runtime.totalMemory() - runtime.freeMemory()
}
