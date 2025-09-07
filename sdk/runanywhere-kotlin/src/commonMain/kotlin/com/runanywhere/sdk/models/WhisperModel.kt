package com.runanywhere.sdk.models

/**
 * Represents a Whisper model configuration
 */
class WhisperModel(
    val type: ModelType
) {
    enum class ModelType(
        val fileName: String,
        val downloadUrl: String,
        val sizeInMB: Int
    ) {
        BASE(
            "ggml-base.en.bin",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
            141
        );

        fun isMultilingual(): Boolean {
            return false // English-only model
        }
    }

    /**
     * Get the local path where the model should be stored
     */
    fun getLocalPath(): String {
        val modelsDir = "${getPlatformBaseDir()}/models"
        val dir = createPlatformFile(modelsDir)
        if (!dir.exists()) {
            createDirectory(modelsDir)
        }
        return "$modelsDir/${type.fileName}"
    }

    /**
     * Check if the model is already downloaded
     */
    fun isDownloaded(): Boolean {
        return createPlatformFile(getLocalPath()).exists()
    }

    /**
     * Get the download URL for the model
     */
    fun getDownloadUrl(): String {
        return type.downloadUrl
    }

    /**
     * Get the model size in MB
     */
    fun getSizeInMB(): Int {
        return type.sizeInMB
    }
}
