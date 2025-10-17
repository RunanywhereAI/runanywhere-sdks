package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.models.DeviceInfoData

/**
 * Device Info Repository Interface
 * Defines operations for device information persistence
 */
interface DeviceInfoRepository {
    suspend fun getCurrentDeviceInfo(): DeviceInfoData?
    suspend fun saveDeviceInfo(deviceInfo: DeviceInfoData)
    suspend fun clearDeviceInfo()
}
