package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere

/**
 * Device information including CPU and GPU capabilities
 * 
 * @property cpuCores Number of CPU cores available
 * @property totalMemoryMB Total system memory in megabytes
 * @property gpuInfo GPU information (null if no GPU available)
 */
data class DeviceInfo(
    val cpuCores: Int,
    val totalMemoryMB: Long,
    val gpuInfo: GPUInfo?
) {
    /**
     * Check if device has GPU acceleration available
     */
    fun hasGPU(): Boolean = gpuInfo?.isAvailable == true
    
    /**
     * Get human-readable device summary
     */
    fun getSummary(): String {
        val gpu = if (hasGPU()) {
            "GPU: ${gpuInfo?.deviceName}"
        } else {
            "GPU: None"
        }
        return "CPU: $cpuCores cores, RAM: ${totalMemoryMB}MB, $gpu"
    }
}

/**
 * GPU information (platform-agnostic)
 */
data class GPUInfo(
    val isAvailable: Boolean,
    val deviceName: String,
    val apiVersion: String,
    val maxMemoryMB: Long
)

/**
 * Get comprehensive device information
 * 
 * Returns information about CPU, memory, and GPU capabilities.
 * Useful for:
 * - Displaying device specs in UI
 * - Making decisions about model selection
 * - Debugging performance issues
 * 
 * Example:
 * ```kotlin
 * val deviceInfo = RunAnywhere.getDeviceInfo()
 * println(deviceInfo.getSummary())
 * // Output: "CPU: 8 cores, RAM: 8192MB, GPU: Adreno 740"
 * 
 * if (deviceInfo.hasGPU()) {
 *     println("GPU VRAM: ${deviceInfo.gpuInfo?.maxMemoryMB}MB")
 * }
 * ```
 * 
 * @return DeviceInfo with CPU, memory, and GPU details
 */
expect suspend fun RunAnywhere.getDeviceInfo(): DeviceInfo

/**
 * Check if GPU acceleration is available
 * 
 * Quick check without retrieving full device information.
 * 
 * @return true if GPU is available and suitable for ML inference
 */
expect suspend fun RunAnywhere.hasGPUAcceleration(): Boolean
