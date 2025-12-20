package com.runanywhere.sdk.data.database.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey
import com.runanywhere.sdk.data.models.APIConfiguration
import com.runanywhere.sdk.data.models.BatteryState
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.ConfigurationSource
import com.runanywhere.sdk.data.models.DeviceInfoData
import com.runanywhere.sdk.data.models.GPUType
import com.runanywhere.sdk.data.models.GenerationConfiguration
import com.runanywhere.sdk.data.models.HardwareConfiguration
import com.runanywhere.sdk.data.models.ModelDownloadConfiguration
import com.runanywhere.sdk.data.models.ModelInfo
import com.runanywhere.sdk.data.models.RoutingConfiguration
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.StorageConfiguration
import com.runanywhere.sdk.data.models.StoredTokens
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventType
import com.runanywhere.sdk.data.models.ThermalState
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Database Entities
 * Room entities based on existing models with type converters
 * Maintains KMP compatibility by using existing data classes
 */

@Entity(tableName = "configurations")
data class ConfigurationEntity(
    @PrimaryKey
    val id: String,

    @ColumnInfo(name = "api_key")
    val apiKey: String,

    @ColumnInfo(name = "base_url")
    val baseURL: String,

    val environment: SDKEnvironment,
    val source: ConfigurationSource,

    @ColumnInfo(name = "last_updated")
    val lastUpdated: Long,

    // Nested configurations stored as JSON strings (converted by TypeConverters)
    val routing: RoutingConfiguration,
    val generation: GenerationConfiguration,
    val storage: StorageConfiguration,
    val api: APIConfiguration,
    val download: ModelDownloadConfiguration,
    val hardware: HardwareConfiguration?
) {
    /**
     * Convert to domain model
     */
    fun toConfigurationData(): ConfigurationData {
        return ConfigurationData(
            id = id,
            routing = routing,
            generation = generation,
            storage = storage,
            api = api,
            download = download,
            hardware = hardware,
            apiKey = apiKey,
            source = source,
            createdAt = lastUpdated,
            updatedAt = lastUpdated
        )
    }

    companion object {
        /**
         * Convert from domain model
         */
        fun fromConfigurationData(config: ConfigurationData): ConfigurationEntity {
            return ConfigurationEntity(
                id = config.id,
                apiKey = config.apiKey ?: "",
                baseURL = config.api.baseURL,
                environment = SDKEnvironment.PRODUCTION, // Default value
                source = config.source,
                lastUpdated = config.updatedAt,
                routing = config.routing,
                generation = config.generation,
                storage = config.storage,
                api = config.api,
                download = config.download,
                hardware = config.hardware
            )
        }
    }
}

@Entity(tableName = "model_info")
data class ModelInfoEntity(
    @PrimaryKey
    val id: String,

    val name: String,
    val category: ModelCategory,
    val format: ModelFormat,
    val framework: InferenceFramework,

    @ColumnInfo(name = "download_url")
    val downloadURL: String,

    @ColumnInfo(name = "local_path")
    val localPath: String?,

    @ColumnInfo(name = "download_size")
    val downloadSize: Long,

    @ColumnInfo(name = "memory_required")
    val memoryRequired: Long,

    @ColumnInfo(name = "compatible_frameworks")
    val compatibleFrameworks: List<String>,

    val version: String,
    val description: String,

    @ColumnInfo(name = "is_built_in")
    val isBuiltIn: Boolean,

    @ColumnInfo(name = "is_downloaded")
    val isDownloaded: Boolean,

    @ColumnInfo(name = "download_progress")
    val downloadProgress: Float,

    @ColumnInfo(name = "last_used")
    val lastUsed: Long?,

    @ColumnInfo(name = "checksum_sha256")
    val checksumSHA256: String?,

    val metadata: Map<String, String>,

    @ColumnInfo(name = "created_at")
    val createdAt: Long,

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long
) {
    /**
     * Convert to domain model
     */
    fun toModelInfo(): ModelInfo {
        return ModelInfo(
            id = id,
            name = name,
            category = category,
            format = format,
            framework = framework,
            downloadURL = downloadURL,
            localPath = localPath,
            downloadSize = downloadSize,
            memoryRequired = memoryRequired,
            compatibleFrameworks = compatibleFrameworks,
            version = version,
            description = description,
            isBuiltIn = isBuiltIn,
            isDownloaded = isDownloaded,
            downloadProgress = downloadProgress,
            lastUsed = lastUsed,
            checksumSHA256 = checksumSHA256,
            metadata = metadata,
            createdAt = createdAt,
            updatedAt = updatedAt
        )
    }

    companion object {
        /**
         * Convert from domain model
         */
        fun fromModelInfo(modelInfo: ModelInfo): ModelInfoEntity {
            return ModelInfoEntity(
                id = modelInfo.id,
                name = modelInfo.name,
                category = modelInfo.category,
                format = modelInfo.format,
                framework = modelInfo.framework,
                downloadURL = modelInfo.downloadURL,
                localPath = modelInfo.localPath,
                downloadSize = modelInfo.downloadSize,
                memoryRequired = modelInfo.memoryRequired,
                compatibleFrameworks = modelInfo.compatibleFrameworks,
                version = modelInfo.version,
                description = modelInfo.description,
                isBuiltIn = modelInfo.isBuiltIn,
                isDownloaded = modelInfo.isDownloaded,
                downloadProgress = modelInfo.downloadProgress,
                lastUsed = modelInfo.lastUsed,
                checksumSHA256 = modelInfo.checksumSHA256,
                metadata = modelInfo.metadata,
                createdAt = modelInfo.createdAt,
                updatedAt = modelInfo.updatedAt
            )
        }
    }
}

@Entity(tableName = "device_info")
data class DeviceInfoEntity(
    @PrimaryKey
    @ColumnInfo(name = "device_id")
    val deviceId: String,

    @ColumnInfo(name = "device_name")
    val deviceName: String,

    @ColumnInfo(name = "system_name")
    val systemName: String,

    @ColumnInfo(name = "system_version")
    val systemVersion: String,

    @ColumnInfo(name = "model_name")
    val modelName: String,

    @ColumnInfo(name = "model_identifier")
    val modelIdentifier: String,

    @ColumnInfo(name = "cpu_type")
    val cpuType: String,

    @ColumnInfo(name = "cpu_architecture")
    val cpuArchitecture: String,

    @ColumnInfo(name = "cpu_core_count")
    val cpuCoreCount: Int,

    @ColumnInfo(name = "cpu_frequency_mhz")
    val cpuFrequencyMHz: Int?,

    @ColumnInfo(name = "total_memory_mb")
    val totalMemoryMB: Long,

    @ColumnInfo(name = "available_memory_mb")
    val availableMemoryMB: Long,

    @ColumnInfo(name = "total_storage_mb")
    val totalStorageMB: Long,

    @ColumnInfo(name = "available_storage_mb")
    val availableStorageMB: Long,

    @ColumnInfo(name = "gpu_type")
    val gpuType: GPUType,

    @ColumnInfo(name = "gpu_name")
    val gpuName: String?,

    @ColumnInfo(name = "gpu_vendor")
    val gpuVendor: String?,

    @ColumnInfo(name = "supports_metal")
    val supportsMetal: Boolean,

    @ColumnInfo(name = "supports_vulkan")
    val supportsVulkan: Boolean,

    @ColumnInfo(name = "supports_opencl")
    val supportsOpenCL: Boolean,

    @ColumnInfo(name = "battery_level")
    val batteryLevel: Float?,

    @ColumnInfo(name = "battery_state")
    val batteryState: BatteryState,

    @ColumnInfo(name = "thermal_state")
    val thermalState: ThermalState,

    @ColumnInfo(name = "is_low_power_mode")
    val isLowPowerMode: Boolean,

    @ColumnInfo(name = "has_cellular")
    val hasCellular: Boolean,

    @ColumnInfo(name = "has_wifi")
    val hasWifi: Boolean,

    @ColumnInfo(name = "has_bluetooth")
    val hasBluetooth: Boolean,

    @ColumnInfo(name = "has_camera")
    val hasCamera: Boolean,

    @ColumnInfo(name = "has_microphone")
    val hasMicrophone: Boolean,

    @ColumnInfo(name = "has_speakers")
    val hasSpeakers: Boolean,

    @ColumnInfo(name = "has_biometric")
    val hasBiometric: Boolean,

    @ColumnInfo(name = "benchmark_score")
    val benchmarkScore: Int?,

    @ColumnInfo(name = "memory_pressure")
    val memoryPressure: Float,

    @ColumnInfo(name = "created_at")
    val createdAt: Long,

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long
) {
    /**
     * Convert to domain model
     */
    fun toDeviceInfoData(): DeviceInfoData {
        return DeviceInfoData(
            deviceId = deviceId,
            deviceName = deviceName,
            systemName = systemName,
            systemVersion = systemVersion,
            modelName = modelName,
            modelIdentifier = modelIdentifier,
            cpuType = cpuType,
            cpuArchitecture = cpuArchitecture,
            cpuCoreCount = cpuCoreCount,
            cpuFrequencyMHz = cpuFrequencyMHz,
            totalMemoryMB = totalMemoryMB,
            availableMemoryMB = availableMemoryMB,
            totalStorageMB = totalStorageMB,
            availableStorageMB = availableStorageMB,
            gpuType = gpuType,
            gpuName = gpuName,
            gpuVendor = gpuVendor,
            supportsMetal = supportsMetal,
            supportsVulkan = supportsVulkan,
            supportsOpenCL = supportsOpenCL,
            batteryLevel = batteryLevel,
            batteryState = batteryState,
            thermalState = thermalState,
            isLowPowerMode = isLowPowerMode,
            hasCellular = hasCellular,
            hasWifi = hasWifi,
            hasBluetooth = hasBluetooth,
            hasCamera = hasCamera,
            hasMicrophone = hasMicrophone,
            hasSpeakers = hasSpeakers,
            hasBiometric = hasBiometric,
            benchmarkScore = benchmarkScore,
            memoryPressure = memoryPressure,
            createdAt = createdAt,
            updatedAt = updatedAt
        )
    }

    companion object {
        /**
         * Convert from domain model
         */
        fun fromDeviceInfoData(deviceInfo: DeviceInfoData): DeviceInfoEntity {
            return DeviceInfoEntity(
                deviceId = deviceInfo.deviceId,
                deviceName = deviceInfo.deviceName,
                systemName = deviceInfo.systemName,
                systemVersion = deviceInfo.systemVersion,
                modelName = deviceInfo.modelName,
                modelIdentifier = deviceInfo.modelIdentifier,
                cpuType = deviceInfo.cpuType,
                cpuArchitecture = deviceInfo.cpuArchitecture,
                cpuCoreCount = deviceInfo.cpuCoreCount,
                cpuFrequencyMHz = deviceInfo.cpuFrequencyMHz,
                totalMemoryMB = deviceInfo.totalMemoryMB,
                availableMemoryMB = deviceInfo.availableMemoryMB,
                totalStorageMB = deviceInfo.totalStorageMB,
                availableStorageMB = deviceInfo.availableStorageMB,
                gpuType = deviceInfo.gpuType,
                gpuName = deviceInfo.gpuName,
                gpuVendor = deviceInfo.gpuVendor,
                supportsMetal = deviceInfo.supportsMetal,
                supportsVulkan = deviceInfo.supportsVulkan,
                supportsOpenCL = deviceInfo.supportsOpenCL,
                batteryLevel = deviceInfo.batteryLevel,
                batteryState = deviceInfo.batteryState,
                thermalState = deviceInfo.thermalState,
                isLowPowerMode = deviceInfo.isLowPowerMode,
                hasCellular = deviceInfo.hasCellular,
                hasWifi = deviceInfo.hasWifi,
                hasBluetooth = deviceInfo.hasBluetooth,
                hasCamera = deviceInfo.hasCamera,
                hasMicrophone = deviceInfo.hasMicrophone,
                hasSpeakers = deviceInfo.hasSpeakers,
                hasBiometric = deviceInfo.hasBiometric,
                benchmarkScore = deviceInfo.benchmarkScore,
                memoryPressure = deviceInfo.memoryPressure,
                createdAt = deviceInfo.createdAt,
                updatedAt = deviceInfo.updatedAt
            )
        }
    }
}

@Entity(tableName = "telemetry_events")
data class TelemetryEventEntity(
    @PrimaryKey
    val id: String,

    val type: TelemetryEventType,
    val name: String,
    val properties: Map<String, String>,
    val metrics: Map<String, Double>,

    @ColumnInfo(name = "session_id")
    val sessionId: String,

    @ColumnInfo(name = "user_id")
    val userId: String?,

    @ColumnInfo(name = "device_id")
    val deviceId: String,

    @ColumnInfo(name = "app_version")
    val appVersion: String?,

    @ColumnInfo(name = "sdk_version")
    val sdkVersion: String,

    val platform: String,

    @ColumnInfo(name = "os_version")
    val osVersion: String,

    val timestamp: Long,
    val duration: Long?,
    val success: Boolean,

    @ColumnInfo(name = "error_code")
    val errorCode: String?,

    @ColumnInfo(name = "error_message")
    val errorMessage: String?,

    @ColumnInfo(name = "is_sent")
    val isSent: Boolean,

    @ColumnInfo(name = "sent_at")
    val sentAt: Long?,

    @ColumnInfo(name = "retry_count")
    val retryCount: Int
) {
    /**
     * Convert to domain model
     */
    fun toTelemetryData(): TelemetryData {
        return TelemetryData(
            id = id,
            type = type,
            name = name,
            properties = properties,
            metrics = metrics,
            sessionId = sessionId,
            userId = userId,
            deviceId = deviceId,
            appVersion = appVersion,
            sdkVersion = sdkVersion,
            platform = platform,
            osVersion = osVersion,
            timestamp = timestamp,
            duration = duration,
            success = success,
            errorCode = errorCode,
            errorMessage = errorMessage,
            isSent = isSent,
            sentAt = sentAt,
            retryCount = retryCount
        )
    }

    companion object {
        /**
         * Convert from domain model
         */
        fun fromTelemetryData(telemetry: TelemetryData): TelemetryEventEntity {
            return TelemetryEventEntity(
                id = telemetry.id,
                type = telemetry.type,
                name = telemetry.name,
                properties = telemetry.properties,
                metrics = telemetry.metrics,
                sessionId = telemetry.sessionId,
                userId = telemetry.userId,
                deviceId = telemetry.deviceId,
                appVersion = telemetry.appVersion,
                sdkVersion = telemetry.sdkVersion,
                platform = telemetry.platform,
                osVersion = telemetry.osVersion,
                timestamp = telemetry.timestamp,
                duration = telemetry.duration,
                success = telemetry.success,
                errorCode = telemetry.errorCode,
                errorMessage = telemetry.errorMessage,
                isSent = telemetry.isSent,
                sentAt = telemetry.sentAt,
                retryCount = telemetry.retryCount
            )
        }
    }
}

@Entity(tableName = "auth_tokens")
data class AuthTokenEntity(
    @PrimaryKey
    val id: String = "current_token",

    @ColumnInfo(name = "access_token")
    val accessToken: String,

    @ColumnInfo(name = "refresh_token")
    val refreshToken: String,

    @ColumnInfo(name = "expires_at")
    val expiresAt: Long,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis()
) {
    /**
     * Convert to domain model
     */
    fun toStoredTokens(): StoredTokens {
        return StoredTokens(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresAt = expiresAt
        )
    }

    companion object {
        /**
         * Convert from domain model
         */
        fun fromStoredTokens(tokens: StoredTokens, id: String = "current_token"): AuthTokenEntity {
            return AuthTokenEntity(
                id = id,
                accessToken = tokens.accessToken,
                refreshToken = tokens.refreshToken,
                expiresAt = tokens.expiresAt
            )
        }
    }
}
