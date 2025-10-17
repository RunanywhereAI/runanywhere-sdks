package com.runanywhere.whisperkit.storage

/**
 * JVM-specific actual implementation of DefaultWhisperStorage
 */
actual class DefaultWhisperStorage : WhisperStorageStrategy() {

    private val implementation = JvmAndroidDefaultWhisperStorage()

    override suspend fun getModelPath(type: com.runanywhere.whisperkit.models.WhisperModelType): String {
        return implementation.getModelPath(type)
    }

    override suspend fun isModelDownloaded(type: com.runanywhere.whisperkit.models.WhisperModelType): Boolean {
        return implementation.isModelDownloaded(type)
    }

    override suspend fun getModelInfo(type: com.runanywhere.whisperkit.models.WhisperModelType): com.runanywhere.whisperkit.models.WhisperModelInfo {
        return implementation.getModelInfo(type)
    }

    override suspend fun getAllModels(): List<com.runanywhere.whisperkit.models.WhisperModelInfo> {
        return implementation.getAllModels()
    }

    override suspend fun deleteModel(type: com.runanywhere.whisperkit.models.WhisperModelType): Boolean {
        return implementation.deleteModel(type)
    }

    override suspend fun getTotalStorageUsed(): Long {
        return implementation.getTotalStorageUsed()
    }

    override suspend fun cleanupOldModels(keepTypes: List<com.runanywhere.whisperkit.models.WhisperModelType>) {
        return implementation.cleanupOldModels(keepTypes)
    }

    override suspend fun updateLastUsed(type: com.runanywhere.whisperkit.models.WhisperModelType) {
        return implementation.updateLastUsed(type)
    }

    override suspend fun downloadModel(
        type: com.runanywhere.whisperkit.models.WhisperModelType,
        onProgress: (com.runanywhere.sdk.storage.DownloadProgress) -> Unit
    ) {
        return implementation.downloadModel(type, onProgress)
    }
}
