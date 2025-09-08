package com.runanywhere.whisperkit.storage

import com.runanywhere.whisperkit.models.*
import kotlinx.coroutines.delay

/**
 * Shared JVM/Android implementation of Whisper storage strategy
 * Since both platforms can use the same file system abstractions and whisper-jni library,
 * we can share the storage logic between them.
 */
class JvmAndroidWhisperStorage : WhisperStorageStrategy {

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
                name = "Whisper ${modelType.name.lowercase().replace("_", "-")} model",
                size = when (modelType) {
                    WhisperModelType.TINY -> 39_000_000L
                    WhisperModelType.BASE -> 74_000_000L
                    WhisperModelType.SMALL -> 244_000_000L
                    WhisperModelType.MEDIUM -> 769_000_000L
                    WhisperModelType.LARGE -> 1550_000_000L
                    WhisperModelType.LARGE_V2 -> 1550_000_000L
                    WhisperModelType.LARGE_V3 -> 1550_000_000L
                },
                localPath = "$modelsBasePath/${modelType.name.lowercase().replace("_", "-")}.bin",
                downloadUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${modelType.name.lowercase().replace("_", "-")}.bin",
                isDownloaded = true // Mock all models as downloaded for development
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
        modelType: WhisperModelType,
        onProgress: (WhisperDownloadProgress) -> Unit
    ) {
        val modelInfo = mockModels[modelType]
            ?: throw IllegalArgumentException("Model not found: $modelType")

        // Simulate download progress for both JVM and Android
        for (progress in 0..100 step 5) {
            delay(25) // Faster simulation for testing
            onProgress(WhisperDownloadProgress(
                modelType = modelType,
                bytesDownloaded = (modelInfo.size * progress / 100),
                totalBytes = modelInfo.size,
                percentage = progress.toDouble(),
                isComplete = progress == 100,
                error = null
            ))
        }

        // Mark as downloaded
        mockModels[modelType] = modelInfo.copy(isDownloaded = true)
    }

    override suspend fun deleteModel(modelType: WhisperModelType) {
        mockModels[modelType]?.let { modelInfo ->
            mockModels[modelType] = modelInfo.copy(
                isDownloaded = false,
                localPath = null
            )
        }
    }

    override suspend fun getModelSize(modelType: WhisperModelType): Long {
        return mockModels[modelType]?.size
            ?: throw IllegalArgumentException("Model not found: $modelType")
    }

    override suspend fun validateModelIntegrity(modelType: WhisperModelType): Boolean {
        // Mock validation - in real implementation would check file integrity
        return isModelDownloaded(modelType)
    }

    override suspend fun cleanup() {
        // Mock cleanup - nothing to do in mock implementation
        // In real implementation, would clean up temporary files, etc.
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
