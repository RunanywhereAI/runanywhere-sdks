package com.runanywhere.sdk.platform

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Device capability detection for GPU acceleration
 * 
 * Provides information about Vulkan GPU availability and capabilities
 * for on-device ML inference acceleration.
 * 
 * Usage:
 * ```kotlin
 * // Check if GPU is available
 * if (DeviceCapabilities.hasVulkanSupport()) {
 *     val gpuInfo = DeviceCapabilities.detectVulkanGPU()
 *     println("GPU: ${gpuInfo.deviceName}")
 *     println("VRAM: ${gpuInfo.maxMemoryMB} MB")
 * }
 * 
 * // List all GPUs
 * val devices = DeviceCapabilities.listVulkanDevices()
 * devices.forEach { gpu ->
 *     println("Found: ${gpu.deviceName}")
 * }
 * ```
 */
object DeviceCapabilities {
    
    private const val TAG = "DeviceCapabilities"
    private val logger = SDKLogger(TAG)
    
    // Cache GPU info to avoid repeated JNI calls
    private var cachedGPUInfo: GPUInfo? = null
    private var cacheInitialized = false
    
    /**
     * Detect Vulkan GPU and return detailed information
     * 
     * This method calls into native code to enumerate Vulkan devices
     * and returns information about the primary GPU.
     * 
     * Results are cached after first call for performance.
     * 
     * @return GPUInfo with device details, or unavailable info if no GPU found
     */
    fun detectVulkanGPU(): GPUInfo {
        if (cacheInitialized && cachedGPUInfo != null) {
            return cachedGPUInfo!!
        }
        
        return try {
            val info = nativeDetectVulkanGPU()
            cachedGPUInfo = info
            cacheInitialized = true
            
            if (info.isAvailable) {
                logger.info( "Vulkan GPU detected: ${info.deviceName}")
                logger.info( "  API: ${info.apiVersion}, VRAM: ${info.maxMemoryMB}MB")
            } else {
                logger.info( "No Vulkan GPU available")
            }
            
            info
        } catch (e: UnsatisfiedLinkError) {
            logger.error("Native library not loaded for GPU detection", throwable = e)
            GPUInfo.unavailable()
        } catch (e: Exception) {
            logger.error("Failed to detect Vulkan GPU", throwable = e)
            GPUInfo.unavailable()
        }
    }
    
    /**
     * Quick check if Vulkan is supported on this device
     * 
     * This is faster than detectVulkanGPU() as it only checks availability
     * without retrieving full device information.
     * 
     * @return true if at least one Vulkan-capable GPU is available
     */
    fun hasVulkanSupport(): Boolean {
        return try {
            nativeIsVulkanSupported()
        } catch (e: UnsatisfiedLinkError) {
            logger.warning("Native library not loaded, assuming no Vulkan support")
            false
        } catch (e: Exception) {
            logger.error("Error checking Vulkan support", throwable = e)
            false
        }
    }
    
    /**
     * List all available Vulkan devices
     * 
     * Some devices may have multiple GPUs (e.g., integrated + discrete).
     * This method returns information about all detected devices.
     * 
     * @return List of GPUInfo for all detected devices (empty if none found)
     */
    fun listVulkanDevices(): List<GPUInfo> {
        return try {
            nativeListVulkanDevices()
        } catch (e: UnsatisfiedLinkError) {
            logger.error("Native library not loaded for device listing", throwable = e)
            emptyList()
        } catch (e: Exception) {
            logger.error("Failed to list Vulkan devices", throwable = e)
            emptyList()
        }
    }
    
    /**
     * Clear cached GPU information
     * 
     * Forces re-detection on next call to detectVulkanGPU().
     * Useful if GPU state may have changed (e.g., after driver update).
     */
    fun clearCache() {
        cachedGPUInfo = null
        cacheInitialized = false
        logger.debug( "GPU info cache cleared")
    }
    
    /**
     * Get recommended GPU usage based on device capabilities
     * 
     * @return true if GPU should be used for ML inference
     */
    fun shouldUseGPU(): Boolean {
        val gpuInfo = detectVulkanGPU()
        return gpuInfo.isSuitableForML()
    }
    
    // =========================================================================
    // Native Methods (JNI)
    // =========================================================================
    
    /**
     * Native method to detect Vulkan GPU
     * Implemented in: sdk/runanywhere-commons/src/jni/device_jni.cpp
     */
    @JvmStatic
    private external fun nativeDetectVulkanGPU(): GPUInfo
    
    /**
     * Native method to check Vulkan support
     * Implemented in: sdk/runanywhere-commons/src/jni/device_jni.cpp
     */
    @JvmStatic
    private external fun nativeIsVulkanSupported(): Boolean
    
    /**
     * Native method to list all Vulkan devices
     * Implemented in: sdk/runanywhere-commons/src/jni/device_jni.cpp
     */
    @JvmStatic
    private external fun nativeListVulkanDevices(): List<GPUInfo>
}
