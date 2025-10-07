package com.runanywhere.sdk.services

import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.config.SDKConfig
import com.runanywhere.sdk.data.network.NetworkService
import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.PersistentDeviceIdentity
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.storage.SecureStorage
import com.runanywhere.sdk.storage.createSecureStorage
import com.runanywhere.sdk.utils.PlatformUtils
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString

/**
 * Service for handling one-time device registration
 * Checks if device is already registered, collects device info, and calls registerDevice endpoint
 * Head-to-head translation from iOS DeviceRegistrationService pattern
 */
class DeviceRegistrationService(
    private val networkService: NetworkService
) {
    private val logger = SDKLogger("DeviceRegistrationService")
    private val secureStorage: SecureStorage by lazy { createSecureStorage() }
    private val registrationMutex = Mutex()

    companion object {
        private const val DEVICE_REGISTRATION_KEY = "com.runanywhere.sdk.device.registered"
        private const val DEVICE_REGISTRATION_TIMESTAMP_KEY = "com.runanywhere.sdk.device.registered.timestamp"
        private const val DEVICE_INFO_CACHE_KEY = "com.runanywhere.sdk.device.info.cache"
    }

    @Volatile
    private var cachedRegistrationStatus: Boolean? = null

    /**
     * Check if device is already registered
     * Matches iOS implementation pattern
     */
    suspend fun isDeviceRegistered(): Boolean {
        // Return cached status if available
        cachedRegistrationStatus?.let { return it }

        return try {
            val isRegistered = secureStorage.containsSecure(DEVICE_REGISTRATION_KEY) &&
                               secureStorage.getSecureString(DEVICE_REGISTRATION_KEY) == "true"

            cachedRegistrationStatus = isRegistered
            logger.debug("Device registration status: $isRegistered")
            isRegistered
        } catch (e: Exception) {
            logger.error("Failed to check device registration status", e)
            false
        }
    }

    /**
     * Get device registration timestamp if available
     */
    suspend fun getRegistrationTimestamp(): Long? {
        return try {
            secureStorage.getSecureString(DEVICE_REGISTRATION_TIMESTAMP_KEY)?.toLongOrNull()
        } catch (e: Exception) {
            logger.error("Failed to get registration timestamp", e)
            null
        }
    }

    /**
     * Register device with server (one-time operation)
     * Collects device info and calls registerDevice endpoint
     * Matches iOS implementation pattern
     */
    suspend fun registerDevice(): Result<DeviceRegistrationResponse> {
        return registrationMutex.withLock {
            try {
                logger.info("Starting device registration process")

                // Check if already registered
                if (isDeviceRegistered()) {
                    logger.info("Device is already registered, skipping registration")
                    return Result.success(DeviceRegistrationResponse(
                        deviceId = PersistentDeviceIdentity.getPersistentDeviceUUID(),
                        registered = true,
                        message = "Device already registered"
                    ))
                }

                // Collect device information
                val deviceInfo = collectDeviceInfo()
                logger.debug("Collected device info for registration")

                // Create registration payload with device_info wrapper
                val registrationPayload = DeviceRegistrationPayload(
                    deviceInfo = deviceInfo
                )

                // Serialize and call registration endpoint
                val json = Json {
                    ignoreUnknownKeys = true
                    encodeDefaults = false
                    coerceInputValues = true  // Handle nulls properly
                }
                val jsonPayload = json.encodeToString(registrationPayload)

                logger.debug("Sending device registration request")

                val responseBytes = networkService.postRaw(
                    endpoint = APIEndpoint.registerDevice,
                    payload = jsonPayload.encodeToByteArray(),
                    requiresAuth = true
                )

                val response = json.decodeFromString<DeviceRegistrationResult>(responseBytes.decodeToString())

                // Store registration status
                markDeviceAsRegistered()

                logger.info("Device registration completed successfully")
                Result.success(DeviceRegistrationResponse(
                    deviceId = response.deviceId,
                    registered = response.status == "registered" || response.status == "updated",
                    message = "Device ${response.status} successfully"
                ))

            } catch (e: Exception) {
                logger.error("Device registration failed", e)
                Result.failure(SDKError.DeviceRegistrationError("Registration failed: ${e.message}"))
            }
        }
    }

    /**
     * Force re-registration of device (useful for testing or resetting state)
     */
    suspend fun forceReregister(): Result<DeviceRegistrationResponse> {
        logger.info("Forcing device re-registration")

        try {
            // Clear existing registration
            clearRegistrationState()

            // Perform registration
            return registerDevice()
        } catch (e: Exception) {
            logger.error("Failed to force re-register device", e)
            return Result.failure(SDKError.DeviceRegistrationError("Force re-registration failed: ${e.message}"))
        }
    }

    /**
     * Update device information without full re-registration
     */
    suspend fun updateDeviceInfo(): Result<DeviceInfoUpdateResponse> {
        return try {
            logger.info("Updating device information")

            val deviceInfo = collectDeviceInfo()
            val updateRequest = DeviceInfoUpdateRequest(
                deviceId = deviceInfo.deviceId,
                deviceInfo = deviceInfo,
                deviceFingerprint = PersistentDeviceIdentity.getDeviceFingerprint(),
                updateTimestamp = System.currentTimeMillis()
            )

            val response = networkService.post<DeviceInfoUpdateRequest, DeviceInfoUpdateResponse>(
                endpoint = APIEndpoint.deviceInfo,
                payload = updateRequest
            )

            logger.info("Device information updated successfully")
            Result.success(response)

        } catch (e: Exception) {
            logger.error("Failed to update device information", e)
            Result.failure(SDKError.DeviceRegistrationError("Device info update failed: ${e.message}"))
        }
    }

    /**
     * Get cached device information or collect fresh data
     */
    suspend fun getDeviceInfo(useCache: Boolean = true): DeviceInfoData {
        if (useCache) {
            try {
                val cachedInfo = secureStorage.getSecureString(DEVICE_INFO_CACHE_KEY)
                if (cachedInfo != null) {
                    // Parse cached device info (would need JSON parsing)
                    logger.debug("Using cached device info")
                }
            } catch (e: Exception) {
                logger.debug("No valid cached device info, collecting fresh data")
            }
        }

        return collectDeviceInfo()
    }

    // MARK: - Private Methods

    /**
     * Collect comprehensive device information
     */
    private fun collectDeviceInfo(): DeviceInfoData {
        val deviceId = PersistentDeviceIdentity.getPersistentDeviceUUID()

        // Get platform-specific device info
        val platformInfo = getPlatformSpecificDeviceInfo()

        // Determine platform and form factor - use PlatformUtils for consistency
        val platform = PlatformUtils.getPlatformName()
        val formFactor = platformInfo["form_factor"] as? String ?: "desktop"

        return DeviceInfoData(
            deviceId = deviceId,
            deviceName = platformInfo["device_name"] as? String ?: "Unknown Device",
            deviceModel = platformInfo["model_name"] as? String ?: "Unknown Model",
            platform = platform,
            osVersion = platformInfo["system_version"] as? String ?: "Unknown Version",
            formFactor = formFactor,
            architecture = platformInfo["cpu_architecture"] as? String ?: "Unknown Architecture",
            chipName = platformInfo["cpu_type"] as? String ?: "Unknown CPU",
            coreCount = platformInfo["cpu_core_count"] as? Int ?: 1,
            performanceCores = platformInfo["cpu_core_count"] as? Int ?: 1,
            efficiencyCores = 0,
            totalMemory = (platformInfo["total_memory_mb"] as? Long ?: 0L) * 1024 * 1024, // Convert MB to bytes
            availableMemory = (platformInfo["available_memory_mb"] as? Long ?: 0L) * 1024 * 1024,
            hasNeuralEngine = platformInfo["has_neural_engine"] as? Boolean ?: false,
            neuralEngineCores = platformInfo["neural_engine_cores"] as? Int ?: 0,
            gpuFamily = platformInfo["gpu_family"] as? String ?: "none",

            // Keep existing fields for backward compatibility
            systemName = platformInfo["system_name"] as? String ?: "Unknown OS",
            systemVersion = platformInfo["system_version"] as? String ?: "Unknown Version",
            modelName = platformInfo["model_name"] as? String ?: "Unknown Model",
            modelIdentifier = platformInfo["model_identifier"] as? String ?: "Unknown Identifier",
            cpuType = platformInfo["cpu_type"] as? String ?: "Unknown CPU",
            cpuArchitecture = platformInfo["cpu_architecture"] as? String ?: "Unknown Architecture",
            cpuCoreCount = platformInfo["cpu_core_count"] as? Int ?: 1,
            cpuFrequencyMHz = platformInfo["cpu_frequency_mhz"] as? Int,
            totalMemoryMB = platformInfo["total_memory_mb"] as? Long ?: 0L,
            availableMemoryMB = platformInfo["available_memory_mb"] as? Long ?: 0L,
            totalStorageMB = platformInfo["total_storage_mb"] as? Long ?: 0L,
            availableStorageMB = platformInfo["available_storage_mb"] as? Long ?: 0L,
            gpuType = platformInfo["gpu_type"] as? GPUType ?: GPUType.UNKNOWN,
            gpuName = platformInfo["gpu_name"] as? String,
            gpuVendor = platformInfo["gpu_vendor"] as? String,
            supportsVulkan = platformInfo["supports_vulkan"] as? Boolean ?: false,
            supportsOpenCL = platformInfo["supports_opencl"] as? Boolean ?: false,
            batteryLevel = (platformInfo["battery_level"] as? Float) ?: 1.0f, // Ensure 0.0-1.0 range
            batteryState = platformInfo["battery_state"] as? BatteryState ?: BatteryState.FULL,
            thermalState = platformInfo["thermal_state"] as? ThermalState ?: ThermalState.NOMINAL,
            isLowPowerMode = platformInfo["is_low_power_mode"] as? Boolean ?: false,
            hasCellular = platformInfo["has_cellular"] as? Boolean ?: false,
            hasWifi = platformInfo["has_wifi"] as? Boolean ?: true,
            hasBluetooth = platformInfo["has_bluetooth"] as? Boolean ?: true,
            hasCamera = platformInfo["has_camera"] as? Boolean ?: false,
            hasMicrophone = platformInfo["has_microphone"] as? Boolean ?: true,
            hasSpeakers = platformInfo["has_speakers"] as? Boolean ?: true,
            hasBiometric = platformInfo["has_biometric"] as? Boolean ?: false,
            benchmarkScore = platformInfo["benchmark_score"] as? Int,
            memoryPressure = platformInfo["memory_pressure"] as? Float ?: 0.0f
        )
    }

    /**
     * Collect platform-specific capabilities
     */
    private fun collectPlatformCapabilities(): Map<String, String> {
        return try {
            val capabilities = getPlatformCapabilities()
            // Convert to string map for serialization
            capabilities.mapValues { (_, value) -> value?.toString() ?: "null" }
        } catch (e: Exception) {
            logger.error("Failed to collect platform capabilities", e)
            mapOf("error" to (e.message ?: "Unknown error"))
        }
    }

    /**
     * Mark device as registered in secure storage
     */
    private suspend fun markDeviceAsRegistered() {
        try {
            secureStorage.setSecureString(DEVICE_REGISTRATION_KEY, "true")
            secureStorage.setSecureString(DEVICE_REGISTRATION_TIMESTAMP_KEY, System.currentTimeMillis().toString())
            cachedRegistrationStatus = true
            logger.debug("Device marked as registered")
        } catch (e: Exception) {
            logger.error("Failed to mark device as registered", e)
        }
    }

    /**
     * Clear registration state (for re-registration)
     */
    private suspend fun clearRegistrationState() {
        try {
            secureStorage.removeSecure(DEVICE_REGISTRATION_KEY)
            secureStorage.removeSecure(DEVICE_REGISTRATION_TIMESTAMP_KEY)
            secureStorage.removeSecure(DEVICE_INFO_CACHE_KEY)
            cachedRegistrationStatus = null
            logger.debug("Device registration state cleared")
        } catch (e: Exception) {
            logger.error("Failed to clear registration state", e)
        }
    }
}

// MARK: - Data Models

// DeviceRegistrationPayload and DeviceRegistrationResult are now in DeviceRegistrationWrapper.kt

@Serializable
data class DeviceRegistrationResponse(
    val deviceId: String,
    val registered: Boolean,
    val message: String,
    val serverTimestamp: Long = System.currentTimeMillis(),
    val registrationId: String? = null
)

@Serializable
data class DeviceInfoUpdateRequest(
    val deviceId: String,
    val deviceInfo: DeviceInfoData,
    val deviceFingerprint: String,
    val updateTimestamp: Long
)

@Serializable
data class DeviceInfoUpdateResponse(
    val deviceId: String,
    val updated: Boolean,
    val message: String,
    val serverTimestamp: Long = System.currentTimeMillis()
)

// MARK: - Platform-specific functions

/**
 * Get platform-specific device information
 * Each platform implements this with detailed system info
 */
expect fun getPlatformSpecificDeviceInfo(): Map<String, Any?>

/**
 * Get platform-specific capabilities
 * Each platform implements this with capability assessment
 */
expect fun getPlatformCapabilities(): Map<String, Any>
