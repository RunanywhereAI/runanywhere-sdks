package com.runanywhere.sdk.services.deviceinfo

import com.runanywhere.sdk.data.models.DeviceInfoData
import com.runanywhere.sdk.data.models.DevicePerformanceMetrics
import com.runanywhere.sdk.data.models.DeviceCapabilityAssessment
import com.runanywhere.sdk.data.repositories.DeviceInfoRepository
import com.runanywhere.sdk.services.sync.SyncCoordinator
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.network.APIClient
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Device Info Service - Enhanced to match iOS functionality
 * Handles device information collection, management, and sync to backend
 */
class DeviceInfoService(
    private val deviceInfoRepository: DeviceInfoRepository,
    private val syncCoordinator: SyncCoordinator?,
    private val apiClient: APIClient?
) {
    private val logger = SDKLogger("DeviceInfoService")
    private var _currentDeviceInfo: DeviceInfoData? = null

    /**
     * Initialize the service and collect initial device information
     */
    suspend fun initialize() {
        logger.info("Initializing DeviceInfoService")

        try {
            // Load or collect current device information
            _currentDeviceInfo = loadCurrentDeviceInfo()

            if (_currentDeviceInfo != null) {
                logger.info("Device info loaded successfully: ${_currentDeviceInfo!!.deviceName}")

                // Publish event
                EventBus.publish(SDKDeviceEvent.DeviceInfoCollected(_currentDeviceInfo!!))

            } else {
                logger.warn("Failed to load device information")
            }

        } catch (e: Exception) {
            logger.error("Failed to initialize DeviceInfoService", e)
            throw e
        }
    }

    /**
     * Load current device information - first from cache, then collect fresh
     */
    suspend fun loadCurrentDeviceInfo(): DeviceInfoData {
        logger.info("Loading current device information")

        // Try to load from repository first (cached data)
        val cachedInfo = try {
            deviceInfoRepository.getCurrentDeviceInfo()
        } catch (e: Exception) {
            logger.warn("Failed to load cached device info: ${e.message}")
            null
        }

        // If cached data is recent (less than 24 hours), use it
        if (cachedInfo != null && isRecentDeviceInfo(cachedInfo)) {
            logger.info("Using cached device info (${cachedInfo.deviceName})")
            return cachedInfo
        }

        // Otherwise collect fresh device information
        logger.info("Collecting fresh device information")
        val freshInfo = collectDeviceInformation()

        // Save to repository
        try {
            deviceInfoRepository.saveDeviceInfo(freshInfo)
            logger.info("Device info saved to repository")
        } catch (e: Exception) {
            logger.warn("Failed to save device info to repository: ${e.message}")
        }

        return freshInfo
    }

    /**
     * Get current device info (cached version)
     */
    suspend fun getCurrentDeviceInfo(): DeviceInfoData? {
        return _currentDeviceInfo ?: loadCurrentDeviceInfo()
    }

    /**
     * Save device info to repository
     */
    suspend fun saveDeviceInfo(deviceInfo: DeviceInfoData) {
        deviceInfoRepository.saveDeviceInfo(deviceInfo)
        _currentDeviceInfo = deviceInfo
    }

    /**
     * Get device ID from current device info
     */
    fun getDeviceId(): String {
        return _currentDeviceInfo?.deviceId ?: "unknown-device-id"
    }

    /**
     * Sync device information to cloud backend
     * This matches iOS DeviceInfoService.syncToCloud() functionality
     */
    suspend fun syncToCloud(): Boolean {
        if (apiClient == null) {
            logger.info("No API client available, skipping cloud sync")
            return false
        }

        val deviceInfo = getCurrentDeviceInfo()
        if (deviceInfo == null) {
            logger.warn("No device info available for cloud sync")
            return false
        }

        return try {
            logger.info("Syncing device info to cloud for device: ${deviceInfo.deviceName}")

            // Use timeout for network operation
            withTimeoutOrNull(30_000) {  // 30 second timeout
                val success = apiClient.syncDeviceInfo(deviceInfo)

                if (success) {
                    logger.info("Device info synced to cloud successfully")
                    EventBus.publish(SDKDeviceEvent.DeviceInfoSynced(deviceInfo))
                } else {
                    logger.warn("Device info sync to cloud failed")
                }

                success
            } ?: run {
                logger.warn("Device info sync to cloud timed out")
                false
            }

        } catch (e: Exception) {
            logger.warn("Device info sync to cloud failed: ${e.message}")
            false
        }
    }

    /**
     * Collect current device performance metrics
     */
    suspend fun collectPerformanceMetrics(): DevicePerformanceMetrics {
        val deviceInfo = getCurrentDeviceInfo()

        return DevicePerformanceMetrics(
            deviceId = deviceInfo?.deviceId ?: "unknown",
            memoryUsagePercent = getCurrentMemoryUsage(),
            memoryPressureLevel = deviceInfo?.memoryPressure ?: 0.0f,
            // Other metrics will be collected by platform-specific implementations
        )
    }

    /**
     * Assess device capabilities for model recommendations
     */
    suspend fun assessDeviceCapabilities(): DeviceCapabilityAssessment {
        val deviceInfo = getCurrentDeviceInfo()

        if (deviceInfo == null) {
            return DeviceCapabilityAssessment(
                deviceInfo = createDefaultDeviceInfo(),
                recommendedModelSizes = listOf("tiny"),
                maxModelSizeMB = 100,
                supportsGPUAcceleration = false,
                supportsParallelProcessing = false,
                batteryOptimized = true,
                performanceRating = 1,
                recommendations = listOf("Use smallest models only")
            )
        }

        val capabilityScore = deviceInfo.capabilityScore

        return DeviceCapabilityAssessment(
            deviceInfo = deviceInfo,
            recommendedModelSizes = getRecommendedModelSizes(capabilityScore),
            maxModelSizeMB = getMaxModelSize(deviceInfo),
            supportsGPUAcceleration = deviceInfo.supportsGPUAcceleration,
            supportsParallelProcessing = deviceInfo.cpuCoreCount >= 4,
            batteryOptimized = deviceInfo.batteryLevel?.let { it > 0.2f } ?: true,
            performanceRating = (capabilityScore / 10).coerceIn(1, 10),
            recommendations = generateRecommendations(deviceInfo)
        )
    }

    /**
     * Platform-specific device information collection
     * This is implemented using expect/actual pattern
     */
    private suspend fun collectDeviceInformation(): DeviceInfoData {
        return collectPlatformDeviceInfo()
    }

    private fun getCurrentMemoryUsage(): Float {
        // Platform-specific implementation
        return 0.0f
    }

    private fun isRecentDeviceInfo(deviceInfo: DeviceInfoData): Boolean {
        val twentyFourHoursInMillis = 24 * 60 * 60 * 1000
        return (System.currentTimeMillis() - deviceInfo.updatedAt) < twentyFourHoursInMillis
    }

    private fun getRecommendedModelSizes(capabilityScore: Int): List<String> {
        return when {
            capabilityScore >= 80 -> listOf("tiny", "base", "small", "medium")
            capabilityScore >= 60 -> listOf("tiny", "base", "small")
            capabilityScore >= 40 -> listOf("tiny", "base")
            else -> listOf("tiny")
        }
    }

    private fun getMaxModelSize(deviceInfo: DeviceInfoData): Long {
        val availableMemoryMB = deviceInfo.availableMemoryMB
        return when {
            availableMemoryMB >= 6144 -> 1500 // 1.5GB for large models
            availableMemoryMB >= 4096 -> 800  // 800MB for medium models
            availableMemoryMB >= 2048 -> 400  // 400MB for small models
            else -> 150  // 150MB for tiny models
        }
    }

    private fun generateRecommendations(deviceInfo: DeviceInfoData): List<String> {
        val recommendations = mutableListOf<String>()

        if (deviceInfo.availableMemoryMB < 2048) {
            recommendations.add("Use tiny models for best performance")
        }

        if (deviceInfo.supportsGPUAcceleration) {
            recommendations.add("GPU acceleration available")
        }

        if (deviceInfo.cpuCoreCount >= 8) {
            recommendations.add("Parallel processing recommended")
        }

        if (deviceInfo.batteryLevel != null && deviceInfo.batteryLevel!! < 0.2f) {
            recommendations.add("Low battery - consider power optimization")
        }

        return recommendations
    }

    private fun createDefaultDeviceInfo(): DeviceInfoData {
        return DeviceInfoData(
            deviceId = "unknown",
            deviceName = "Unknown Device",
            systemName = "Unknown",
            systemVersion = "Unknown",
            modelName = "Unknown",
            modelIdentifier = "Unknown",
            cpuType = "Unknown",
            cpuArchitecture = "Unknown",
            cpuCoreCount = 1,
            totalMemoryMB = 1024,
            availableMemoryMB = 512,
            totalStorageMB = 8192,
            availableStorageMB = 1024,
            gpuType = com.runanywhere.sdk.data.models.GPUType.UNKNOWN
        )
    }
}

/**
 * Platform-specific device information collection
 * Implemented using expect/actual pattern in platform-specific source sets
 */
expect suspend fun collectPlatformDeviceInfo(): DeviceInfoData

/**
 * Device-related events for EventBus
 */
sealed class SDKDeviceEvent {
    data class DeviceInfoCollected(val deviceInfo: DeviceInfoData) : SDKDeviceEvent()
    data class DeviceInfoSynced(val deviceInfo: DeviceInfoData) : SDKDeviceEvent()
    data class DeviceInfoSyncFailed(val error: String) : SDKDeviceEvent()
}

// Extension to publish device events
fun EventBus.publish(event: SDKDeviceEvent) {
    // For now, we'll publish as configuration events until we add device events to EventBus
    when (event) {
        is SDKDeviceEvent.DeviceInfoCollected -> {
            // Convert to a configuration event for compatibility
            publish(com.runanywhere.sdk.events.SDKConfigurationEvent.Updated("device_info_collected", event.deviceInfo.deviceId))
        }
        is SDKDeviceEvent.DeviceInfoSynced -> {
            publish(com.runanywhere.sdk.events.SDKConfigurationEvent.Updated("device_info_synced", event.deviceInfo.deviceId))
        }
        is SDKDeviceEvent.DeviceInfoSyncFailed -> {
            publish(com.runanywhere.sdk.events.SDKConfigurationEvent.Updated("device_info_sync_failed", event.error))
        }
    }
}
