package com.runanywhere.sdk.data.models

import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerialName

/**
 * Device info data models
 * One-to-one translation from iOS Swift device info models to Kotlin
 */

/**
 * Platform-specific API level access
 */
expect fun getPlatformAPILevel(): Int

/**
 * GPU Type enumeration
 * Equivalent to iOS GPUType enum (adapted for Android)
 */
@Serializable
enum class GPUType {
    @SerialName("adreno")
    ADRENO,
    @SerialName("mali")
    MALI,
    @SerialName("power_vr")
    POWER_VR,
    @SerialName("tegra")
    TEGRA,
    @SerialName("vivante")
    VIVANTE,
    @SerialName("unknown")
    UNKNOWN
}

/**
 * Battery state enumeration
 * Equivalent to iOS BatteryState enum
 */
@Serializable
enum class BatteryState {
    @SerialName("unknown")
    UNKNOWN,
    @SerialName("unplugged")
    UNPLUGGED,
    @SerialName("charging")
    CHARGING,
    @SerialName("full")
    FULL
}

/**
 * Thermal state enumeration
 * Equivalent to iOS ThermalState enum
 */
@Serializable
enum class ThermalState {
    @SerialName("nominal")
    NOMINAL,
    @SerialName("fair")
    FAIR,
    @SerialName("serious")
    SERIOUS,
    @SerialName("critical")
    CRITICAL
}

/**
 * Device info data class
 * One-to-one translation from iOS DeviceInfoData
 */
@Serializable
data class DeviceInfoData(
    @SerialName("device_id")
    val deviceId: String,
    @SerialName("device_name")
    val deviceName: String,
    @SerialName("device_model")
    val deviceModel: String? = null,
    @SerialName("platform")
    val platform: String? = null, // "ios", "android", "macos", "windows", "linux", "web"
    @SerialName("os_version")
    val osVersion: String? = null,
    @SerialName("form_factor")
    val formFactor: String? = null, // "phone", "tablet", "desktop", "laptop", "watch", "tv"
    @SerialName("architecture")
    val architecture: String? = null,
    @SerialName("chip_name")
    val chipName: String? = null,
    @SerialName("core_count")
    val coreCount: Int? = null,
    @SerialName("performance_cores")
    val performanceCores: Int? = null,
    @SerialName("efficiency_cores")
    val efficiencyCores: Int? = null,
    @SerialName("total_memory")
    val totalMemory: Long? = null, // in bytes
    @SerialName("available_memory")
    val availableMemory: Long? = null, // in bytes
    @SerialName("has_neural_engine")
    val hasNeuralEngine: Boolean? = null,
    @SerialName("neural_engine_cores")
    val neuralEngineCores: Int? = null,
    @SerialName("gpu_family")
    val gpuFamily: String? = null,

    // Keep existing fields for backward compatibility
    @SerialName("system_name")
    val systemName: String = "Android",
    @SerialName("system_version")
    val systemVersion: String,
    @SerialName("model_name")
    val modelName: String,
    @SerialName("model_identifier")
    val modelIdentifier: String,

    // Hardware specifications
    @SerialName("cpu_type")
    val cpuType: String,
    @SerialName("cpu_architecture")
    val cpuArchitecture: String,
    @SerialName("cpu_core_count")
    val cpuCoreCount: Int,
    @SerialName("cpu_frequency_mhz")
    val cpuFrequencyMHz: Int? = null,

    @SerialName("total_memory_mb")
    val totalMemoryMB: Long,
    @SerialName("available_memory_mb")
    val availableMemoryMB: Long,

    @SerialName("total_storage_mb")
    val totalStorageMB: Long,
    @SerialName("available_storage_mb")
    val availableStorageMB: Long,

    // GPU information
    @SerialName("gpu_type")
    val gpuType: GPUType,
    @SerialName("gpu_name")
    val gpuName: String? = null,
    @SerialName("gpu_vendor")
    val gpuVendor: String? = null,
    @SerialName("supports_metal")
    val supportsMetal: Boolean = false, // Always false on Android
    @SerialName("supports_vulkan")
    val supportsVulkan: Boolean = false,
    @SerialName("supports_opencl")
    val supportsOpenCL: Boolean = false,

    // Power and thermal
    @SerialName("battery_level")
    val batteryLevel: Float? = null, // 0.0 to 1.0 (not 0-100)
    @SerialName("battery_state")
    val batteryState: BatteryState = BatteryState.UNKNOWN,
    @SerialName("thermal_state")
    val thermalState: ThermalState = ThermalState.NOMINAL,
    @SerialName("is_low_power_mode")
    val isLowPowerMode: Boolean = false,

    // Network capabilities
    @SerialName("has_cellular")
    val hasCellular: Boolean = false,
    @SerialName("has_wifi")
    val hasWifi: Boolean = false,
    @SerialName("has_bluetooth")
    val hasBluetooth: Boolean = false,

    // Sensors and capabilities
    @SerialName("has_camera")
    val hasCamera: Boolean = false,
    @SerialName("has_microphone")
    val hasMicrophone: Boolean = false,
    @SerialName("has_speakers")
    val hasSpeakers: Boolean = false,
    @SerialName("has_biometric")
    val hasBiometric: Boolean = false,

    // Performance indicators
    @SerialName("benchmark_score")
    val benchmarkScore: Int? = null,
    @SerialName("memory_pressure")
    val memoryPressure: Float = 0.0f, // 0.0 to 1.0

    // Timestamps
    @SerialName("created_at")
    val createdAt: Long = getCurrentTimeMillis(),
    @SerialName("updated_at")
    val updatedAt: Long = getCurrentTimeMillis()
) {

    /**
     * Check if device has sufficient memory for model
     * Equivalent to iOS computed property
     */
    fun hasSufficientMemory(requiredMB: Long): Boolean {
        return availableMemoryMB >= requiredMB
    }

    /**
     * Check if device has sufficient storage for model
     * Equivalent to iOS computed property
     */
    fun hasSufficientStorage(requiredMB: Long): Boolean {
        return availableStorageMB >= requiredMB
    }

    /**
     * Check if device supports GPU acceleration
     * Equivalent to iOS computed property
     */
    val supportsGPUAcceleration: Boolean
        get() = supportsVulkan || supportsOpenCL || gpuType != GPUType.UNKNOWN

    /**
     * Get device capability score (0-100)
     * Used for model selection recommendations
     */
    val capabilityScore: Int
        get() {
            var score = 0

            // Memory contribution (0-30 points)
            score += when {
                totalMemoryMB >= 8192 -> 30
                totalMemoryMB >= 6144 -> 25
                totalMemoryMB >= 4096 -> 20
                totalMemoryMB >= 3072 -> 15
                totalMemoryMB >= 2048 -> 10
                else -> 5
            }

            // CPU contribution (0-25 points)
            score += when {
                cpuCoreCount >= 8 -> 25
                cpuCoreCount >= 6 -> 20
                cpuCoreCount >= 4 -> 15
                cpuCoreCount >= 2 -> 10
                else -> 5
            }

            // GPU contribution (0-20 points)
            score += when (gpuType) {
                GPUType.ADRENO -> 20
                GPUType.MALI -> 18
                GPUType.POWER_VR -> 15
                GPUType.TEGRA -> 17
                GPUType.VIVANTE -> 10
                GPUType.UNKNOWN -> 5
            }

            // System version contribution (0-15 points)
            val apiLevel = getPlatformAPILevel()
            score += when {
                apiLevel >= 34 -> 15 // Android 14+
                apiLevel >= 31 -> 12 // Android 12+
                apiLevel >= 29 -> 10 // Android 10+
                apiLevel >= 26 -> 8  // Android 8+
                else -> 5
            }

            // Storage contribution (0-10 points)
            score += when {
                availableStorageMB >= 10240 -> 10 // 10GB+
                availableStorageMB >= 5120 -> 8   // 5GB+
                availableStorageMB >= 2048 -> 6   // 2GB+
                availableStorageMB >= 1024 -> 4   // 1GB+
                else -> 2
            }

            return minOf(score, 100)
        }
}

/**
 * Device fingerprint for identification
 * Used to uniquely identify device across app installations
 */
@Serializable
data class DeviceFingerprint(
    @SerialName("device_id")
    val deviceId: String,
    @SerialName("hardware_fingerprint")
    val hardwareFingerprint: String,
    @SerialName("software_fingerprint")
    val softwareFingerprint: String,
    @SerialName("display_fingerprint")
    val displayFingerprint: String,
    @SerialName("created_at")
    val createdAt: Long = getCurrentTimeMillis()
) {

    /**
     * Generate comprehensive device fingerprint
     * Combines hardware and software characteristics
     */
    val combinedFingerprint: String
        get() = "${hardwareFingerprint}_${softwareFingerprint}_${displayFingerprint}".hashCode().toString()
}

/**
 * Device performance metrics
 * Used for benchmarking and optimization
 */
@Serializable
data class DevicePerformanceMetrics(
    @SerialName("device_id")
    val deviceId: String,

    // CPU metrics
    @SerialName("cpu_usage_percent")
    val cpuUsagePercent: Float = 0.0f,
    @SerialName("cpu_temperature")
    val cpuTemperature: Float? = null,

    // Memory metrics
    @SerialName("memory_usage_percent")
    val memoryUsagePercent: Float = 0.0f,
    @SerialName("memory_pressure_level")
    val memoryPressureLevel: Float = 0.0f,

    // GPU metrics (if available)
    @SerialName("gpu_usage_percent")
    val gpuUsagePercent: Float? = null,
    @SerialName("gpu_temperature")
    val gpuTemperature: Float? = null,

    // Battery metrics
    @SerialName("battery_drain_rate")
    val batteryDrainRate: Float? = null, // mAh per hour
    @SerialName("power_consumption_mw")
    val powerConsumptionMW: Float? = null,

    // Performance scores
    @SerialName("single_core_score")
    val singleCoreScore: Int? = null,
    @SerialName("multi_core_score")
    val multiCoreScore: Int? = null,
    @SerialName("gpu_score")
    val gpuScore: Int? = null,

    @SerialName("measured_at")
    val measuredAt: Long = getCurrentTimeMillis()
)

/**
 * Device capability assessment
 * Recommendations for model usage based on device specs
 */
data class DeviceCapabilityAssessment(
    val deviceInfo: DeviceInfoData,
    val recommendedModelSizes: List<String>, // e.g., ["tiny", "base", "small"]
    val maxModelSizeMB: Long,
    val supportsGPUAcceleration: Boolean,
    val supportsParallelProcessing: Boolean,
    val batteryOptimized: Boolean,
    val performanceRating: Int, // 1-10 scale
    val recommendations: List<String>
)
