package com.runanywhere.sdk.models

/**
 * Model mapper for WhisperJNI implementation on JVM platform.
 *
 * Maps common model IDs to WhisperJNI-compatible model file paths.
 * This follows the exact iOS implementation pattern for consistency.
 */
object JvmWhisperJNIModelMapper {

    /**
     * Standard model mappings from common model names to whisper.cpp model filenames
     * These correspond to the standard whisper.cpp model distribution
     */
    private val modelMappings = mapOf(
        // Tiny model (39 MB) - fastest, lowest accuracy
        "whisper-tiny" to "ggml-tiny.bin",
        "tiny" to "ggml-tiny.bin",
        "openai_whisper-tiny" to "ggml-tiny.bin",

        // Base model (142 MB) - good balance
        "whisper-base" to "ggml-base.bin",
        "base" to "ggml-base.bin",
        "openai_whisper-base" to "ggml-base.bin",

        // Small model (244 MB) - better accuracy
        "whisper-small" to "ggml-small.bin",
        "small" to "ggml-small.bin",
        "openai_whisper-small" to "ggml-small.bin",

        // Medium model (769 MB) - high accuracy
        "whisper-medium" to "ggml-medium.bin",
        "medium" to "ggml-medium.bin",
        "openai_whisper-medium" to "ggml-medium.bin",

        // Large model (1550 MB) - highest accuracy
        "whisper-large" to "ggml-large-v3.bin",
        "large" to "ggml-large-v3.bin",
        "whisper-large-v3" to "ggml-large-v3.bin",
        "openai_whisper-large" to "ggml-large-v3.bin",
        "openai_whisper-large-v3" to "ggml-large-v3.bin"
    )

    /**
     * Default model used when no specific model is requested
     */
    private const val DEFAULT_MODEL = "ggml-base.bin"

    /**
     * Map a model ID to the corresponding whisper.cpp model filename
     *
     * @param modelId The model identifier (e.g., "whisper-base", "tiny", "openai_whisper-small")
     * @return The corresponding model filename (e.g., "ggml-base.bin")
     */
    fun mapModelIdToFileName(modelId: String?): String {
        return if (modelId == null) {
            DEFAULT_MODEL
        } else {
            modelMappings[modelId.lowercase()] ?: DEFAULT_MODEL
        }
    }

    /**
     * Map a model ID to a full model path within the models directory
     *
     * @param modelId The model identifier
     * @param modelsDir The base directory where models are stored (default: "models/")
     * @return The full relative path to the model file
     */
    fun mapModelIdToPath(modelId: String?, modelsDir: String = "models/"): String {
        val fileName = mapModelIdToFileName(modelId)
        return if (modelsDir.endsWith("/")) {
            "$modelsDir$fileName"
        } else {
            "$modelsDir/$fileName"
        }
    }

    /**
     * Check if a model ID is supported
     *
     * @param modelId The model identifier to check
     * @return True if the model is supported, false otherwise
     */
    fun isModelSupported(modelId: String?): Boolean {
        return modelId == null || modelMappings.containsKey(modelId.lowercase())
    }

    /**
     * Get all supported model IDs
     *
     * @return Set of all supported model identifiers
     */
    fun getSupportedModelIds(): Set<String> {
        return modelMappings.keys.toSet()
    }

    /**
     * Get model size information in MB
     * Based on standard whisper.cpp model sizes
     */
    fun getModelSize(modelId: String?): Long {
        val fileName = mapModelIdToFileName(modelId)
        return when {
            fileName.contains("tiny") -> 39L
            fileName.contains("base") -> 142L
            fileName.contains("small") -> 244L
            fileName.contains("medium") -> 769L
            fileName.contains("large") -> 1550L
            else -> 142L // default to base model size
        }
    }

    /**
     * Get model type information
     */
    fun getModelType(modelId: String?): String {
        val fileName = mapModelIdToFileName(modelId)
        return when {
            fileName.contains("tiny") -> "tiny"
            fileName.contains("small") -> "small"
            fileName.contains("medium") -> "medium"
            fileName.contains("large") -> "large"
            else -> "base"
        }
    }
}
