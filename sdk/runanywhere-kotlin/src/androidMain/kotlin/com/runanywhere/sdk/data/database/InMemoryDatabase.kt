package com.runanywhere.sdk.data.database

import com.runanywhere.sdk.data.database.dao.*
import com.runanywhere.sdk.data.database.entities.*
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * In-memory implementation of database for development/testing
 * This can be easily swapped with the real Room database implementation
 * when ready for production.
 *
 * Note: This doesn't extend RunAnywhereDatabase as that's a Room database.
 * Instead, it provides the same DAOs for compatibility.
 */
class InMemoryDatabase {

    fun configurationDao(): ConfigurationDao = InMemoryConfigurationDao()
    fun modelInfoDao(): ModelInfoDao = InMemoryModelInfoDao()
    fun deviceInfoDao(): DeviceInfoDao = InMemoryDeviceInfoDao()
    fun telemetryDao(): TelemetryDao = InMemoryTelemetryDao()
    fun authTokenDao(): AuthTokenDao = InMemoryAuthTokenDao()

    companion object {
        @Volatile
        private var INSTANCE: InMemoryDatabase? = null

        /**
         * Get singleton instance of the in-memory database
         * This method signature matches the real database for easy swapping
         */
        fun getInstance(): InMemoryDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = InMemoryDatabase()
                INSTANCE = instance
                instance
            }
        }
    }
}

/**
 * In-memory implementation of TelemetryDao
 */
class InMemoryTelemetryDao : TelemetryDao {
    private val events = mutableMapOf<String, TelemetryEventEntity>()
    private val mutex = Mutex()

    override suspend fun getEventById(eventId: String): TelemetryEventEntity? = mutex.withLock {
        events[eventId]
    }

    override suspend fun getAllEvents(): List<TelemetryEventEntity> = mutex.withLock {
        events.values.sortedByDescending { it.timestamp }
    }

    override suspend fun getEventsBySession(sessionId: String): List<TelemetryEventEntity> = mutex.withLock {
        events.values.filter { it.sessionId == sessionId }.sortedByDescending { it.timestamp }
    }

    override suspend fun getEventsByType(eventType: TelemetryEventType): List<TelemetryEventEntity> = mutex.withLock {
        events.values.filter { it.type == eventType }.sortedByDescending { it.timestamp }
    }

    override suspend fun getUnsentEvents(): List<TelemetryEventEntity> = mutex.withLock {
        events.values.filter { !it.isSent }.sortedBy { it.timestamp }
    }

    override suspend fun getSentEvents(): List<TelemetryEventEntity> = mutex.withLock {
        events.values.filter { it.isSent }.sortedByDescending { it.timestamp }
    }

    override suspend fun getFailedEvents(): List<TelemetryEventEntity> = mutex.withLock {
        events.values.filter { !it.success }.sortedByDescending { it.timestamp }
    }

    override suspend fun getEventsByTimeRange(startTime: Long, endTime: Long): List<TelemetryEventEntity> = mutex.withLock {
        events.values.filter { it.timestamp in startTime..endTime }.sortedByDescending { it.timestamp }
    }

    override suspend fun getEventsByDevice(deviceId: String): List<TelemetryEventEntity> = mutex.withLock {
        events.values.filter { it.deviceId == deviceId }.sortedByDescending { it.timestamp }
    }

    override suspend fun getRecentEvents(limit: Int): List<TelemetryEventEntity> = mutex.withLock {
        events.values.sortedByDescending { it.timestamp }.take(limit)
    }

    override suspend fun insertEvent(event: TelemetryEventEntity) = mutex.withLock {
        events[event.id] = event
    }

    override suspend fun insertEvents(events: List<TelemetryEventEntity>) = mutex.withLock {
        events.forEach { event ->
            this.events[event.id] = event
        }
    }

    override suspend fun updateEvent(event: TelemetryEventEntity) = mutex.withLock {
        events[event.id] = event
    }

    override suspend fun markEventsSent(eventIds: List<String>, sentAt: Long) = mutex.withLock {
        eventIds.forEach { id ->
            events[id]?.let { event ->
                events[id] = event.copy(isSent = true, sentAt = sentAt)
            }
        }
    }

    override suspend fun incrementRetryCount(eventIds: List<String>) = mutex.withLock {
        eventIds.forEach { id ->
            events[id]?.let { event ->
                events[id] = event.copy(retryCount = event.retryCount + 1)
            }
        }
    }

    override suspend fun deleteEvent(event: TelemetryEventEntity) = mutex.withLock {
        events.remove(event.id)
        Unit
    }

    override suspend fun deleteEventById(eventId: String) = mutex.withLock {
        events.remove(eventId)
        Unit
    }

    override suspend fun deleteEventsByIds(eventIds: List<String>) = mutex.withLock {
        eventIds.forEach { events.remove(it) }
    }

    override suspend fun deleteAllEvents() = mutex.withLock {
        events.clear()
    }

    override suspend fun deleteOldEvents(timestamp: Long) = mutex.withLock {
        val toRemove = events.entries.filter { it.value.timestamp < timestamp }.map { it.key }
        toRemove.forEach { events.remove(it) }
    }

    override suspend fun deleteOldSentEvents(timestamp: Long) = mutex.withLock {
        events.entries.removeIf { it.value.isSent && (it.value.sentAt ?: 0) < timestamp }
        Unit
    }

    override suspend fun getEventCount(): Int = mutex.withLock {
        events.size
    }

    override suspend fun getUnsentEventCount(): Int = mutex.withLock {
        events.values.count { !it.isSent }
    }

    override suspend fun getFailedEventCount(): Int = mutex.withLock {
        events.values.count { !it.success }
    }

    override suspend fun getEventCountByType(eventType: TelemetryEventType): Int = mutex.withLock {
        events.values.count { it.type == eventType }
    }

    override suspend fun getAverageDurationByType(eventType: TelemetryEventType): Double? = mutex.withLock {
        val durations = events.values.filter { it.type == eventType && it.duration != null }.mapNotNull { it.duration }
        if (durations.isEmpty()) null else durations.average()
    }
}

/**
 * Placeholder implementations for other DAOs
 * These can be implemented as needed when moving to real database
 */
class InMemoryConfigurationDao : ConfigurationDao {
    override suspend fun getCurrentConfiguration() = null
    override suspend fun getConfigurationBySource(source: com.runanywhere.sdk.data.models.ConfigurationSource) = null
    override suspend fun getConfigurationByEnvironment(environment: com.runanywhere.sdk.data.models.SDKEnvironment) = null
    override suspend fun getAllConfigurations() = emptyList<ConfigurationEntity>()
    override suspend fun insertConfiguration(configuration: ConfigurationEntity) {}
    override suspend fun updateConfiguration(configuration: ConfigurationEntity) {}
    override suspend fun deleteConfiguration(configuration: ConfigurationEntity) {}
    override suspend fun deleteConfigurationById(id: String) {}
    override suspend fun deleteAllConfigurations() {}
    override suspend fun deleteOldConfigurations(timestamp: Long) {}
    override suspend fun getConfigurationCount() = 0
}

class InMemoryModelInfoDao : ModelInfoDao {
    override suspend fun getModelById(modelId: String) = null
    override suspend fun getAllModels() = emptyList<ModelInfoEntity>()
    override suspend fun getModelsByFrameworks(frameworks: List<InferenceFramework>) = emptyList<ModelInfoEntity>()
    override suspend fun getModelsByCategory(category: ModelCategory) = emptyList<ModelInfoEntity>()
    override suspend fun getDownloadedModels() = emptyList<ModelInfoEntity>()
    override suspend fun getBuiltInModels() = emptyList<ModelInfoEntity>()
    override suspend fun getModelsBySizeLimit(maxSize: Long) = emptyList<ModelInfoEntity>()
    override suspend fun searchModels(query: String) = emptyList<ModelInfoEntity>()
    override suspend fun getRecentlyUsedModels(limit: Int) = emptyList<ModelInfoEntity>()
    override suspend fun getModelsBySize() = emptyList<ModelInfoEntity>()
    override suspend fun insertModel(model: ModelInfoEntity) {}
    override suspend fun insertModels(models: List<ModelInfoEntity>) {}
    override suspend fun updateModel(model: ModelInfoEntity) {}
    override suspend fun updateDownloadStatus(modelId: String, isDownloaded: Boolean, updatedAt: Long) {}
    override suspend fun updateDownloadProgress(modelId: String, progress: Float, updatedAt: Long) {}
    override suspend fun updateLocalPath(modelId: String, localPath: String?, updatedAt: Long) {}
    override suspend fun updateLastUsed(modelId: String, lastUsed: Long, updatedAt: Long) {}
    override suspend fun deleteModel(model: ModelInfoEntity) {}
    override suspend fun deleteModelById(modelId: String) {}
    override suspend fun deleteAllModels() {}
    override suspend fun deleteUndownloadedModels() {}
    override suspend fun getModelCount() = 0
    override suspend fun getDownloadedModelCount() = 0
    override suspend fun getTotalDownloadedSize() = null
}

class InMemoryDeviceInfoDao : DeviceInfoDao {
    override suspend fun getDeviceInfoById(deviceId: String) = null
    override suspend fun getCurrentDeviceInfo() = null
    override suspend fun getAllDeviceInfo() = emptyList<DeviceInfoEntity>()
    override suspend fun insertDeviceInfo(deviceInfo: DeviceInfoEntity) {}
    override suspend fun updateDeviceInfo(deviceInfo: DeviceInfoEntity) {}
    override suspend fun updateDynamicInfo(deviceId: String, availableMemoryMB: Long, availableStorageMB: Long, batteryLevel: Float?, memoryPressure: Float, updatedAt: Long) {}
    override suspend fun deleteDeviceInfo(deviceInfo: DeviceInfoEntity) {}
    override suspend fun deleteDeviceInfoById(deviceId: String) {}
    override suspend fun deleteAllDeviceInfo() {}
    override suspend fun deleteOldDeviceInfo(timestamp: Long) {}
    override suspend fun getDeviceInfoCount() = 0
}

class InMemoryAuthTokenDao : AuthTokenDao {
    override suspend fun getTokenById(tokenId: String) = null
    override suspend fun getCurrentToken() = null
    override suspend fun getValidToken(currentTime: Long) = null
    override suspend fun getAllTokens() = emptyList<AuthTokenEntity>()
    override suspend fun insertToken(token: AuthTokenEntity) {}
    override suspend fun updateToken(token: AuthTokenEntity) {}
    override suspend fun deleteToken(token: AuthTokenEntity) {}
    override suspend fun deleteTokenById(tokenId: String) {}
    override suspend fun deleteAllTokens() {}
    override suspend fun deleteExpiredTokens(currentTime: Long) {}
    override suspend fun getTokenCount() = 0
    override suspend fun getValidTokenCount(currentTime: Long) = 0
}
