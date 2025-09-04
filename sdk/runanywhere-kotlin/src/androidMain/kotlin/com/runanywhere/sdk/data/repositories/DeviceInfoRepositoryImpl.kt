package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.database.RunAnywhereDatabase
import com.runanywhere.sdk.data.models.DeviceInfoData
import com.runanywhere.sdk.data.repositories.DeviceInfoRepository

/**
 * Android implementation of DeviceInfoRepository
 */
class DeviceInfoRepositoryImpl(
    private val database: RunAnywhereDatabase
) : DeviceInfoRepository {

    override suspend fun getCurrentDeviceInfo(): DeviceInfoData? {
        // TODO: Implement database fetch
        return null
    }

    override suspend fun saveDeviceInfo(deviceInfo: DeviceInfoData) {
        // TODO: Implement database save
    }

    override suspend fun clearDeviceInfo() {
        // TODO: Implement clear
    }
}
