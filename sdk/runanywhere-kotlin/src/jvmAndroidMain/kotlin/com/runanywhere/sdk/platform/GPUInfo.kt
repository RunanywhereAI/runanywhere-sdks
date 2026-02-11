package com.runanywhere.sdk.platform

/**
 * Information about a Vulkan-capable GPU device
 * 
 * @property isAvailable Whether Vulkan GPU is available on this device
 * @property deviceName GPU device name (e.g., "Adreno 740", "Mali-G78")
 * @property driverVersion GPU driver version string
 * @property apiVersion Vulkan API version (e.g., "1.3.0")
 * @property maxMemoryMB Total GPU memory in megabytes (VRAM)
 * @property supportsCompute Whether GPU supports compute shaders (required for ML)
 */
data class GPUInfo(
    val isAvailable: Boolean,
    val deviceName: String,
    val driverVersion: String,
    val apiVersion: String,
    val maxMemoryMB: Long,
    val supportsCompute: Boolean
) {
    /**
     * Check if this GPU is suitable for ML inference
     */
    fun isSuitableForML(): Boolean {
        return isAvailable && supportsCompute && maxMemoryMB >= 512
    }
    
    /**
     * Get human-readable GPU description
     */
    fun getDescription(): String {
        return if (isAvailable) {
            "$deviceName (Vulkan $apiVersion, ${maxMemoryMB}MB VRAM)"
        } else {
            "No GPU available"
        }
    }
    
    /**
     * Check if Vulkan version meets minimum requirement
     */
    fun meetsMinimumVulkanVersion(major: Int, minor: Int): Boolean {
        if (!isAvailable) return false
        
        val parts = apiVersion.split(".")
        if (parts.size < 2) return false
        
        val vkMajor = parts[0].toIntOrNull() ?: 0
        val vkMinor = parts[1].toIntOrNull() ?: 0
        
        return vkMajor > major || (vkMajor == major && vkMinor >= minor)
    }
    
    companion object {
        /**
         * Create a GPUInfo representing no GPU available
         */
        fun unavailable(): GPUInfo {
            return GPUInfo(
                isAvailable = false,
                deviceName = "None",
                driverVersion = "0.0.0",
                apiVersion = "0.0.0",
                maxMemoryMB = 0,
                supportsCompute = false
            )
        }
    }
}
