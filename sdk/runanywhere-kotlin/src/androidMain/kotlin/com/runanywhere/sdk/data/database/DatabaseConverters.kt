package com.runanywhere.sdk.data.database

import androidx.room.TypeConverter
import com.runanywhere.sdk.data.models.APIConfiguration
import com.runanywhere.sdk.data.models.BatteryState
import com.runanywhere.sdk.data.models.ConfigurationSource
import com.runanywhere.sdk.data.models.GPUType
import com.runanywhere.sdk.data.models.GenerationConfiguration
import com.runanywhere.sdk.data.models.HardwareConfiguration
import com.runanywhere.sdk.data.models.ModelDownloadConfiguration
import com.runanywhere.sdk.data.models.RoutingConfiguration
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.StorageConfiguration
import com.runanywhere.sdk.data.models.TelemetryEventType
import com.runanywhere.sdk.data.models.ThermalState
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.serialization.json.Json

/**
 * Database Type Converters
 * Converts complex data types for Room database storage
 * Uses existing models with kotlinx.serialization for JSON conversion
 */
class DatabaseConverters {
    private val json =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
        }

    // Enum Converters
    @TypeConverter
    fun fromSDKEnvironment(value: SDKEnvironment): String = value.name

    @TypeConverter
    fun toSDKEnvironment(value: String): SDKEnvironment = SDKEnvironment.valueOf(value)

    @TypeConverter
    fun fromConfigurationSource(value: ConfigurationSource): String = value.name

    @TypeConverter
    fun toConfigurationSource(value: String): ConfigurationSource = ConfigurationSource.valueOf(value)

    @TypeConverter
    fun fromModelCategory(value: ModelCategory): String = value.name

    @TypeConverter
    fun toModelCategory(value: String): ModelCategory = ModelCategory.valueOf(value)

    @TypeConverter
    fun fromModelFormat(value: ModelFormat): String = value.name

    @TypeConverter
    fun toModelFormat(value: String): ModelFormat = ModelFormat.valueOf(value)

    @TypeConverter
    fun fromInferenceFramework(value: InferenceFramework): String = value.name

    @TypeConverter
    fun toInferenceFramework(value: String): InferenceFramework = InferenceFramework.valueOf(value)

    @TypeConverter
    fun fromGPUType(value: GPUType): String = value.name

    @TypeConverter
    fun toGPUType(value: String): GPUType = GPUType.valueOf(value)

    @TypeConverter
    fun fromBatteryState(value: BatteryState): String = value.name

    @TypeConverter
    fun toBatteryState(value: String): BatteryState = BatteryState.valueOf(value)

    @TypeConverter
    fun fromThermalState(value: ThermalState): String = value.name

    @TypeConverter
    fun toThermalState(value: String): ThermalState = ThermalState.valueOf(value)

    @TypeConverter
    fun fromTelemetryEventType(value: TelemetryEventType): String = value.name

    @TypeConverter
    fun toTelemetryEventType(value: String): TelemetryEventType = TelemetryEventType.valueOf(value)

    // Configuration Objects Converters
    @TypeConverter
    fun fromRoutingConfiguration(value: RoutingConfiguration): String = json.encodeToString(value)

    @TypeConverter
    fun toRoutingConfiguration(value: String): RoutingConfiguration = json.decodeFromString(value)

    @TypeConverter
    fun fromGenerationConfiguration(value: GenerationConfiguration): String = json.encodeToString(value)

    @TypeConverter
    fun toGenerationConfiguration(value: String): GenerationConfiguration = json.decodeFromString(value)

    @TypeConverter
    fun fromStorageConfiguration(value: StorageConfiguration): String = json.encodeToString(value)

    @TypeConverter
    fun toStorageConfiguration(value: String): StorageConfiguration = json.decodeFromString(value)

    @TypeConverter
    fun fromAPIConfiguration(value: APIConfiguration): String = json.encodeToString(value)

    @TypeConverter
    fun toAPIConfiguration(value: String): APIConfiguration = json.decodeFromString(value)

    @TypeConverter
    fun fromModelDownloadConfiguration(value: ModelDownloadConfiguration): String = json.encodeToString(value)

    @TypeConverter
    fun toModelDownloadConfiguration(value: String): ModelDownloadConfiguration = json.decodeFromString(value)

    @TypeConverter
    fun fromHardwareConfiguration(value: HardwareConfiguration?): String? = value?.let { json.encodeToString(it) }

    @TypeConverter
    fun toHardwareConfiguration(value: String?): HardwareConfiguration? = value?.let { json.decodeFromString(it) }

    // Collection Converters
    @TypeConverter
    fun fromStringList(value: List<String>): String = json.encodeToString(value)

    @TypeConverter
    fun toStringList(value: String): List<String> = json.decodeFromString(value)

    @TypeConverter
    fun fromStringMap(value: Map<String, String>): String = json.encodeToString(value)

    @TypeConverter
    fun toStringMap(value: String): Map<String, String> = json.decodeFromString(value)

    @TypeConverter
    fun fromDoubleMap(value: Map<String, Double>): String = json.encodeToString(value)

    @TypeConverter
    fun toDoubleMap(value: String): Map<String, Double> = json.decodeFromString(value)

    // Nullable converters for optional fields
    @TypeConverter
    fun fromNullableLong(value: Long?): String? = value?.toString()

    @TypeConverter
    fun toNullableLong(value: String?): Long? = value?.toLongOrNull()

    @TypeConverter
    fun fromNullableInt(value: Int?): String? = value?.toString()

    @TypeConverter
    fun toNullableInt(value: String?): Int? = value?.toIntOrNull()

    @TypeConverter
    fun fromNullableFloat(value: Float?): String? = value?.toString()

    @TypeConverter
    fun toNullableFloat(value: String?): Float? = value?.toFloatOrNull()

    @TypeConverter
    fun fromNullableString(value: String?): String? = value

    @TypeConverter
    fun toNullableString(value: String?): String? = value
}
