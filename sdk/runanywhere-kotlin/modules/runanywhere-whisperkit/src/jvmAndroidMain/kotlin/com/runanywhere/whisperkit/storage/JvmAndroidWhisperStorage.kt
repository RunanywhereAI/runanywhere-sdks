package com.runanywhere.whisperkit.storage

import com.runanywhere.whisperkit.models.*
import com.runanywhere.sdk.storage.DownloadProgress
import com.runanywhere.sdk.storage.DownloadState
import kotlinx.coroutines.delay

/**
 * Shared JVM/Android implementation of Whisper storage strategy
 * Since both platforms can use the same file system abstractions and whisper-jni library,
 * we can share the storage logic between them.
 */
class JvmAndroidWhisperStorage : WhisperStorageStrategy() {

    // Default models path that works for both JVM and Android
    private val modelsBasePath = when {
        // Detect Android environment
        isAndroidEnvironment() -> "/android_asset/models"
        // JVM environment (desktop/IntelliJ)
        else -> System.getProperty("user.home") + "/.runanywhere/models"
    }

    private val mockModels = mutableMapOf<WhisperModelType, WhisperModelInfo>().apply {
        // Initialize with mock model info that represents whisper-jni models
        WhisperModelType.values().forEach { modelType ->
            put(modelType, WhisperModelInfo(
                type = modelType,
                localPath = "$modelsBasePath/${modelType.name.lowercase().replace("_", "-")}.bin",
                isDownloaded = true, // Mock all models as downloaded for development
                lastUsed = System.currentTimeMillis()
            ))
        }
    }

    override suspend fun getModelPath(modelType: WhisperModelType): String {
        return mockModels[modelType]?.localPath
            ?: throw IllegalArgumentException("Model not found: $modelType")
    }

    override suspend fun getAllModels(): List<WhisperModelInfo> {
        return mockModels.values.toList()
    }

    override suspend fun isModelDownloaded(modelType: WhisperModelType): Boolean {
        return mockModels[modelType]?.isDownloaded == true
    }

    override suspend fun downloadModel(
        type: WhisperModelType,
        onProgress: (DownloadProgress) -> Unit
    ) {
        val modelInfo = mockModels[type]
            ?: throw IllegalArgumentException("Model not found: $type")

        // Simulate download progress for both JVM and Android
        for (progress in 0..100 step 5) {
            delay(25) // Faster simulation for testing
            val sizeMB = type.approximateSizeMB * 1024 * 1024L
            onProgress(DownloadProgress(
                bytesDownloaded = (sizeMB * progress / 100),
                totalBytes = sizeMB,
                state = if (progress == 100) DownloadState.COMPLETED else DownloadState.DOWNLOADING
            ))
        }

        // Mark as downloaded
        mockModels[type] = modelInfo.copy(isDownloaded = true)
    }

    override suspend fun deleteModel(type: WhisperModelType): Boolean {
        mockModels[type]?.let { modelInfo ->
            mockModels[type] = modelInfo.copy(
                isDownloaded = false,
                localPath = null
            )
            return true
        }
        return false
    }

    override suspend fun getModelInfo(type: WhisperModelType): WhisperModelInfo {
        return mockModels[type] ?: WhisperModelInfo(
            type = type,
            localPath = null,
            isDownloaded = false
        )
    }

    override suspend fun getTotalStorageUsed(): Long {
        return mockModels.values
            .filter { it.isDownloaded }
            .sumOf { it.type.approximateSizeMB * 1024 * 1024L }
    }

    override suspend fun cleanupOldModels(keepTypes: List<WhisperModelType>) {
        mockModels.keys.forEach { type ->
            if (!keepTypes.contains(type)) {
                mockModels[type]?.let { modelInfo ->
                    mockModels[type] = modelInfo.copy(isDownloaded = false)
                }
            }
        }
    }

    override suspend fun updateLastUsed(type: WhisperModelType) {
        mockModels[type]?.let { modelInfo ->
            mockModels[type] = modelInfo.copy(
                lastUsed = System.currentTimeMillis()
            )
        }
    }

    /**
     * Detect if we're running in Android environment
     * This allows the same code to work differently on JVM vs Android
     */
    private fun isAndroidEnvironment(): Boolean {
        return try {
            Class.forName("android.os.Build")
            true
        } catch (e: ClassNotFoundException) {
            false
        }
    }

    /**
     * Get platform-specific models directory
     */
    fun getModelsDirectory(): String {
        return modelsBasePath
    }

    /**
     * Get whisper-jni library info
     */
    fun getWhisperJniInfo(): Map<String, String> {
        return mapOf(
            "library" to "whisper-jni",
            "models_path" to modelsBasePath,
            "platform" to if (isAndroidEnvironment()) "Android" else "JVM",
            "supported_formats" to "ggml, gguf"
        )
    }
}
