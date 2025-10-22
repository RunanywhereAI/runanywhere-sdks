package com.runanywhere.sdk.data.repositories

import com.runanywhere.sdk.data.database.RunAnywhereDatabase
import com.runanywhere.sdk.data.database.entities.DeviceInfoEntity
import com.runanywhere.sdk.data.models.DeviceInfoData
import com.runanywhere.sdk.data.repositories.DeviceInfoRepository
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Android implementation of DeviceInfoRepository using Room database
 */
class DeviceInfoRepositoryImpl(
    private val database: RunAnywhereDatabase
) : DeviceInfoRepository {

    private val logger = SDKLogger("DeviceInfoRepository")

    override suspend fun getCurrentDeviceInfo(): DeviceInfoData? {
        return try {
            val entity = database.deviceInfoDao().getCurrentDeviceInfo()
            entity?.toDeviceInfoData()
        } catch (e: Exception) {
            logger.error("Failed to get device info from database", e)
            null
        }
    }

    // Additional helper methods (not from interface)
    suspend fun getDeviceInfoByDeviceId(deviceId: String): DeviceInfoData? {
        return try {
            val entity = database.deviceInfoDao().getDeviceInfoById(deviceId)
            entity?.toDeviceInfoData()
        } catch (e: Exception) {
            logger.error("Failed to get device info by ID from database", e)
            null
        }
    }

    suspend fun getAllDeviceInfo(): List<DeviceInfoData> {
        return try {
            database.deviceInfoDao().getAllDeviceInfo()
                .map { it.toDeviceInfoData() }
        } catch (e: Exception) {
            logger.error("Failed to get all device info from database", e)
            emptyList()
        }
    }

    override suspend fun saveDeviceInfo(deviceInfo: DeviceInfoData) {
        try {
            val entity = DeviceInfoEntity.fromDeviceInfoData(deviceInfo)
            database.deviceInfoDao().insertDeviceInfo(entity)
            logger.debug("Device info saved to database with ID: ${deviceInfo.deviceId}")
        } catch (e: Exception) {
            logger.error("Failed to save device info to database", e)
            throw e
        }
    }

    suspend fun updateDeviceInfo(deviceInfo: DeviceInfoData) {
        try {
            val entity = DeviceInfoEntity.fromDeviceInfoData(deviceInfo)
            database.deviceInfoDao().updateDeviceInfo(entity)
            logger.debug("Device info updated in database with ID: ${deviceInfo.deviceId}")
        } catch (e: Exception) {
            logger.error("Failed to update device info in database", e)
            throw e
        }
    }

    suspend fun deleteDeviceInfo(deviceId: String) {
        try {
            database.deviceInfoDao().deleteDeviceInfoById(deviceId)
            logger.debug("Device info deleted from database with ID: $deviceId")
        } catch (e: Exception) {
            logger.error("Failed to delete device info from database", e)
            throw e
        }
    }

    override suspend fun clearDeviceInfo() {
        try {
            database.deviceInfoDao().deleteAllDeviceInfo()
            logger.info("All device info cleared from database")
        } catch (e: Exception) {
            logger.error("Failed to clear device info from database", e)
            throw e
        }
    }

    suspend fun getDeviceInfoCount(): Int {
        return try {
            database.deviceInfoDao().getDeviceInfoCount()
        } catch (e: Exception) {
            logger.error("Failed to get device info count from database", e)
            0
        }
    }

    suspend fun deleteOldDeviceInfo(olderThanTimestamp: Long) {
        try {
            database.deviceInfoDao().deleteOldDeviceInfo(olderThanTimestamp)
            logger.debug("Deleted old device info older than $olderThanTimestamp")
        } catch (e: Exception) {
            logger.error("Failed to delete old device info", e)
        }
    }
}
