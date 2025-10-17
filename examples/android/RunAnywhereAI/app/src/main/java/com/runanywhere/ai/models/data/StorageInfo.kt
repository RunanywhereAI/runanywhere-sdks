package com.runanywhere.ai.models.data

data class StorageInfo(
    val totalAppStorage: Long,
    val usedAppStorage: Long,
    val totalDeviceStorage: Long,
    val availableDeviceStorage: Long,
    val modelsStorage: Long,
    val cacheSize: Long,
    val downloadedModelsCount: Int,
    val storedModels: List<StoredModel>
) {
    val freeAppStorage: Long
        get() = totalAppStorage - usedAppStorage

    val appStoragePercentage: Float
        get() = if (totalAppStorage > 0) (usedAppStorage.toFloat() / totalAppStorage) else 0f

    val deviceStoragePercentage: Float
        get() = if (totalDeviceStorage > 0) {
            ((totalDeviceStorage - availableDeviceStorage).toFloat() / totalDeviceStorage)
        } else 0f
}

data class StoredModel(
    val modelInfo: ModelUiState, // This now uses the type alias
    val fileSize: Long,
    val lastAccessed: Long,
    val accessCount: Int = 0,
    val filePath: String
)
