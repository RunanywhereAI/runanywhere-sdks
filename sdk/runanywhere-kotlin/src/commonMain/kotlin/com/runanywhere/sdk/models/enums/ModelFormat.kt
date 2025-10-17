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
            return values().find { it.value == value } ?: UNKNOWN
        }
    }
}
