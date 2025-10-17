package com.runanywhere.sdk.models

/**
 * Model formats supported
 * Matches iOS ModelFormat enum
 */
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
        fun fromExtension(ext: String): ModelFormat? {
            return values().firstOrNull { it.value == ext.lowercase() }
        }
    }
}
