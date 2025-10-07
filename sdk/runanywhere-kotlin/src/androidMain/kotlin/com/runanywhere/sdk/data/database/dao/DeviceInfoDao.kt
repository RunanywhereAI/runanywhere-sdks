package com.runanywhere.sdk.data.database.dao

import androidx.room.*
import com.runanywhere.sdk.data.database.entities.DeviceInfoEntity

/**
 * Device Info DAO
 * Room DAO for device information following iOS patterns
 */
@Dao
interface DeviceInfoDao {

    @Query("SELECT * FROM device_info WHERE device_id = :deviceId")
    suspend fun getDeviceInfoById(deviceId: String): DeviceInfoEntity?

    @Query("SELECT * FROM device_info ORDER BY updated_at DESC LIMIT 1")
    suspend fun getCurrentDeviceInfo(): DeviceInfoEntity?

    @Query("SELECT * FROM device_info")
    suspend fun getAllDeviceInfo(): List<DeviceInfoEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertDeviceInfo(deviceInfo: DeviceInfoEntity)

    @Update
    suspend fun updateDeviceInfo(deviceInfo: DeviceInfoEntity)

    @Query("""
        UPDATE device_info
        SET available_memory_mb = :availableMemoryMB,
            available_storage_mb = :availableStorageMB,
            battery_level = :batteryLevel,
            memory_pressure = :memoryPressure,
            updated_at = :updatedAt
        WHERE device_id = :deviceId
    """)
    suspend fun updateDynamicInfo(
        deviceId: String,
        availableMemoryMB: Long,
        availableStorageMB: Long,
        batteryLevel: Float?,
        memoryPressure: Float,
        updatedAt: Long
    )

    @Delete
    suspend fun deleteDeviceInfo(deviceInfo: DeviceInfoEntity)

    @Query("DELETE FROM device_info WHERE device_id = :deviceId")
    suspend fun deleteDeviceInfoById(deviceId: String)

    @Query("DELETE FROM device_info")
    suspend fun deleteAllDeviceInfo()

    @Query("DELETE FROM device_info WHERE updated_at < :timestamp")
    suspend fun deleteOldDeviceInfo(timestamp: Long)

    @Query("SELECT COUNT(*) FROM device_info")
    suspend fun getDeviceInfoCount(): Int
}
