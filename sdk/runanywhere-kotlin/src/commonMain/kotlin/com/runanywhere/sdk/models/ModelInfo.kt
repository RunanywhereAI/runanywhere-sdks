package com.runanywhere.sdk.models

import com.runanywhere.sdk.data.models.fileExists
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import com.runanywhere.sdk.utils.SimpleInstant
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

/**
 * Information about a model - exact match with iOS ModelInfo
 */
@Serializable
data class ModelInfo(
    // Essential identifiers
    val id: String,
    val name: String,
    val category: ModelCategory,

    // Format and location
    val format: ModelFormat,
    val downloadURL: String? = null,
    var localPath: String? = null,

    // Size information (in bytes)
    val downloadSize: Long? = null,
    val memoryRequired: Long? = null,

    // Integrity verification
    val sha256Checksum: String? = null,
    val md5Checksum: String? = null,

    // Framework compatibility
    val compatibleFrameworks: List<LLMFramework> = emptyList(),
    val preferredFramework: LLMFramework? = null,

    // Model-specific capabilities (optional based on category)
    val contextLength: Int? = null,
    val supportsThinking: Boolean = false,

    // Optional metadata
    val metadata: ModelInfoMetadata? = null,

    // Tracking fields
    val source: ConfigurationSource = ConfigurationSource.REMOTE,
    val createdAt: SimpleInstant = SimpleInstant.now(),
    var updatedAt: SimpleInstant = SimpleInstant.now(),
    var syncPending: Boolean = false,

    // Usage tracking
    var lastUsed: SimpleInstant? = null,
    var usageCount: Int = 0,

    // Non-persistent runtime properties
    @Transient
    var additionalProperties: Map<String, String> = emptyMap()
) {
    /**
     * Whether this model is downloaded and available locally
     * Matches iOS: checks both localPath existence AND file existence on disk
     */
    val isDownloaded: Boolean
        get() {
            val path = localPath ?: return false

            // Built-in models are always available (like iOS)
            if (path.startsWith("builtin://") || path.startsWith("builtin:")) {
                return true
            }

            // Check if file/directory actually exists on disk (matches iOS behavior)
            return fileExists(path)
        }

    /**
     * Whether this model is available for use (downloaded and locally accessible)
     */
    val isAvailable: Boolean
        get() = isDownloaded

    /**
     * Get the effective context length (with defaults based on category)
     */
    val effectiveContextLength: Int?
        get() = if (category.requiresContextLength) {
            contextLength ?: 2048
        } else {
            contextLength
        }

    /**
     * Get the effective thinking support (based on category)
     */
    val effectiveSupportsThinking: Boolean
        get() = if (category.supportsThinking) supportsThinking else false
}

/**
 * Model information metadata - exact match with iOS
 */
@Serializable
data class ModelInfoMetadata(
    val author: String? = null,
    val license: String? = null,
    val tags: List<String> = emptyList(),
    val description: String? = null,
    val trainingDataset: String? = null,
    val baseModel: String? = null,
    val quantizationLevel: QuantizationLevel? = null,
    val version: String? = null,
    val minOSVersion: String? = null,
    val minMemory: Long? = null
)

/**
 * Quantization level for models
 */
@Serializable
enum class QuantizationLevel(val value: String) {
    Q2_K("q2_k"),
    Q3_K_S("q3_k_s"),
    Q3_K_M("q3_k_m"),
    Q3_K_L("q3_k_l"),
    Q4_0("q4_0"),
    Q4_1("q4_1"),
    Q4_K_S("q4_k_s"),
    Q4_K_M("q4_k_m"),
    Q5_0("q5_0"),
    Q5_1("q5_1"),
    Q5_K_S("q5_k_s"),
    Q5_K_M("q5_k_m"),
    Q6_K("q6_k"),
    Q6_K_L("q6_k_l"),
    Q8_0("q8_0"),
    F16("f16"),
    F32("f32");

    companion object {
        fun fromValue(value: String): QuantizationLevel? {
            return entries.find { it.value.equals(value, ignoreCase = true) }
        }
    }
}

/**
 * Configuration source
 */
@Serializable
enum class ConfigurationSource {
    LOCAL,
    REMOTE,
    DEFAULT
}
