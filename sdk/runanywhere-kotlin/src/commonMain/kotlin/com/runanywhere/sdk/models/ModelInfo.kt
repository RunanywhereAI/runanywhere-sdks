package com.runanywhere.sdk.models

import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import java.io.File
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant

/**
 * Information about a model - exact match with iOS ModelInfo
 */
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
    val createdAt: Instant = Clock.System.now(),
    var updatedAt: Instant = Clock.System.now(),
    var syncPending: Boolean = false,

    // Usage tracking
    var lastUsed: Date? = null,
    var usageCount: Int = 0,

    // Non-persistent runtime properties
    @Transient
    var additionalProperties: Map<String, String> = emptyMap()
) {
    /**
     * Whether this model is downloaded and available locally
     */
    val isDownloaded: Boolean
        get() = localPath?.let { File(it).exists() } ?: false

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
enum class ConfigurationSource {
    LOCAL,
    REMOTE,
    DEFAULT
}
