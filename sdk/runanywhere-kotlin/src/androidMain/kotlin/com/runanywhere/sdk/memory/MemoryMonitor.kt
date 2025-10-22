package com.runanywhere.sdk.memory

import android.app.ActivityManager
import android.content.Context
import android.os.Debug

/**
 * Android implementation of memory monitoring
 */
actual class MemoryMonitor {

    companion object {
        private var applicationContext: Context? = null

        fun initialize(context: Context) {
            applicationContext = context.applicationContext
        }
    }

    actual fun getTotalMemory(): Long {
        val activityManager = applicationContext?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager?.getMemoryInfo(memoryInfo)
        return memoryInfo?.totalMem ?: 0L
    }

    actual fun getAvailableMemory(): Long {
        val activityManager = applicationContext?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager?.getMemoryInfo(memoryInfo)
        return memoryInfo?.availMem ?: 0L
    }

    actual fun getUsedMemory(): Long {
        // Get native heap usage
        val nativeHeap = Debug.getNativeHeapAllocatedSize()

        // Get Dalvik/ART heap usage
        val runtime = Runtime.getRuntime()
        val dalvikHeap = runtime.totalMemory() - runtime.freeMemory()

        return nativeHeap + dalvikHeap
    }
}
