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
        TINY(
            "ggml-tiny.bin",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
            39
        ),
        BASE(
            "ggml-base.bin",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
            74
        ),
        SMALL(
            "ggml-small.bin",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
            244
        ),
        MEDIUM(
            "ggml-medium.bin",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
            769
        ),
        LARGE(
            "ggml-large-v3.bin",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
            1550
        );

        fun isMultilingual(): Boolean {
            return this != TINY // All models except tiny are multilingual
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
