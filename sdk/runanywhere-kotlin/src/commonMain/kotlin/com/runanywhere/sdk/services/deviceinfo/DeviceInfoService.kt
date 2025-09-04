package com.runanywhere.sdk.services.deviceinfo

import com.runanywhere.sdk.data.models.DeviceInfoData
import com.runanywhere.sdk.data.repositories.DeviceInfoRepository
import com.runanywhere.sdk.services.sync.SyncCoordinator

/**
 * Device Info Service
 * Common implementation for device information management
 */
class DeviceInfoService(
    private val deviceInfoRepository: DeviceInfoRepository,
    private val syncCoordinator: SyncCoordinator?
) {
    suspend fun getCurrentDeviceInfo(): DeviceInfoData? {
        return deviceInfoRepository.getCurrentDeviceInfo()
    }

    suspend fun saveDeviceInfo(deviceInfo: DeviceInfoData) {
        deviceInfoRepository.saveDeviceInfo(deviceInfo)
    }

    fun getDeviceId(): String {
        // Platform-specific implementation will provide the actual device ID
        return "default-device-id"
    }

    suspend fun initialize() {
        // Initialize device info service
    }
}
