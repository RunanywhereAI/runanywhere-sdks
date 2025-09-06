package com.runanywhere.sdk.models

import android.content.Context
import java.io.File

/**
 * Represents a Whisper model configuration
 */
class WhisperModel(
    val type: ModelType,
    private val context: Context? = null
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
        val modelsDir = context?.getExternalFilesDir("models")
            ?: File(System.getProperty("user.home"), ".runanywhere/models")

        if (!modelsDir.exists()) {
            modelsDir.mkdirs()
        }

        return File(modelsDir, type.fileName).absolutePath
    }

    /**
     * Check if the model is already downloaded
     */
    fun isDownloaded(): Boolean {
        return File(getLocalPath()).exists()
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
