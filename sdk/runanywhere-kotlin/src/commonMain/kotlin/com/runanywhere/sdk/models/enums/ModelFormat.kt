package com.runanywhere.sdk.models.enums

import kotlinx.serialization.Serializable

/**
 * Model formats supported - exact match with iOS
 */
@Serializable
enum class ModelFormat(val value: String) {
    MLMODEL("mlmodel"),
    MLPACKAGE("mlpackage"),
    TFLITE("tflite"),
    ONNX("onnx"),
    ORT("ort"),
    SAFETENSORS("safetensors"),
    GGUF("gguf"),
    GGML("ggml"),
    MLX("mlx"),
    PTE("pte"),
    BIN("bin"),
    WEIGHTS("weights"),
    CHECKPOINT("checkpoint"),
    UNKNOWN("unknown");

    companion object {
        fun fromValue(value: String): ModelFormat {
            return entries.find { it.value == value } ?: UNKNOWN
        }

        /**
         * Auto-detect model format from URL
         * Matches iOS ModelFormat.detectFromURL(_:)
         */
        fun detectFromURL(url: String): ModelFormat {
            val path = url.lowercase()

            return when {
                path.contains(".gguf") -> GGUF
                path.contains(".ggml") -> GGML
                path.contains(".mlmodel") -> MLMODEL
                path.contains(".mlpackage") -> MLPACKAGE
                path.contains(".onnx") -> ONNX
                path.contains(".ort") -> ORT
                path.contains(".tflite") -> TFLITE
                path.contains(".mlx") -> MLX
                path.contains(".bin") -> BIN
                path.contains(".safetensors") -> SAFETENSORS
                path.contains(".pte") -> PTE
                path.contains(".weights") -> WEIGHTS
                path.contains(".checkpoint") || path.contains(".ckpt") -> CHECKPOINT
                // Check for common model hosting patterns
                url.contains("huggingface.co") -> when {
                    path.contains("gguf") -> GGUF
                    path.contains("onnx") -> ONNX
                    else -> UNKNOWN
                }
                else -> UNKNOWN
            }
        }
    }
}
