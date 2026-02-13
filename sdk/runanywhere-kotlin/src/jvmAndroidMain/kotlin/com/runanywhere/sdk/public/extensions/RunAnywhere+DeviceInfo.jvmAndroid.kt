package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.platform.DeviceCapabilities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * JVM/Android implementation of device info
 */
actual suspend fun RunAnywhere.getDeviceInfo(): DeviceInfo = withContext(Dispatchers.IO) {
    requireInitialized()
    
    // Get CPU info
    val cpuCores = Runtime.getRuntime().availableProcessors()
    
    // Get memory info
    val totalMemoryMB = Runtime.getRuntime().maxMemory() / (1024 * 1024)
    
    // Get GPU info
    val platformGPUInfo = DeviceCapabilities.detectVulkanGPU()
    val gpuInfo = if (platformGPUInfo.isAvailable) {
        GPUInfo(
            isAvailable = true,
            deviceName = platformGPUInfo.deviceName,
            apiVersion = platformGPUInfo.apiVersion,
            maxMemoryMB = platformGPUInfo.maxMemoryMB
        )
    } else {
        null
    }
    
    DeviceInfo(
        cpuCores = cpuCores,
        totalMemoryMB = totalMemoryMB,
        gpuInfo = gpuInfo
    )
}

/**
 * JVM/Android implementation of GPU check
 */
actual suspend fun RunAnywhere.hasGPUAcceleration(): Boolean = withContext(Dispatchers.IO) {
    requireInitialized()
    DeviceCapabilities.shouldUseGPU()
}
