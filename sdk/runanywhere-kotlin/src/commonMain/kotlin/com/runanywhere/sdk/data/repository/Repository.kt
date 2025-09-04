package com.runanywhere.sdk.data.repository

import com.runanywhere.sdk.data.models.*

/**
 * Repository interfaces
 * One-to-one translation from iOS repository protocols
 */

/**
 * Configuration Repository
 * Handles configuration data persistence and retrieval
 */
interface ConfigurationRepository {
    suspend fun fetchRemoteConfiguration(apiKey: String): ConfigurationData?
    suspend fun getLocalConfiguration(): ConfigurationData?
    suspend fun saveLocalConfiguration(configuration: ConfigurationData)
    suspend fun syncToRemote(configuration: ConfigurationData)
}

/**
 * Model Info Repository
 * Handles model information persistence and retrieval
 */
interface ModelInfoRepository {
    suspend fun getModel(modelId: String): ModelInfo?
    suspend fun saveModel(model: ModelInfo)
    suspend fun getModelsForFrameworks(frameworks: List<LLMFramework>): List<ModelInfo>
    suspend fun getAllModels(): List<ModelInfo>
    suspend fun deleteModel(modelId: String)
    suspend fun searchModels(criteria: ModelSearchCriteria): List<ModelInfo>
    suspend fun fetchRemoteModels(): List<ModelInfo>
}

/**
 * Device Info Repository
 * Handles device information persistence and retrieval
 */
interface DeviceInfoRepository {
    suspend fun getCurrentDeviceInfo(): DeviceInfoData?
    suspend fun saveDeviceInfo(deviceInfo: DeviceInfoData)
    suspend fun syncToRemote(deviceInfo: DeviceInfoData)
}

/**
 * Telemetry Repository
 * Handles telemetry data persistence and transmission
 */
interface TelemetryRepository {
    suspend fun saveEvent(event: TelemetryData)
    suspend fun getAllEvents(): List<TelemetryData>
    suspend fun getUnsentEvents(): List<TelemetryData>
    suspend fun markEventsSent(eventIds: List<String>, sentAt: Long)
    suspend fun sendBatch(batch: TelemetryBatch)
}
