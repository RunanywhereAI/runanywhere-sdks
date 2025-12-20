package com.runanywhere.sdk.public.models

import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelInfoMetadata
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Model registration data for declaring models during framework registration.
 * Exact match with iOS ModelRegistration struct.
 *
 * All parameters use strongly-typed enums - no strings for framework or modality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/ModelRegistration.swift
 */
data class ModelRegistration(
    /**
     * Unique identifier for the model.
     * If not provided, auto-generated from URL's last path component.
     */
    val id: String,
    /**
     * Display name for the model.
     * If not provided, defaults to URL's last path component.
     */
    val name: String,
    /**
     * URL to download the model from (HuggingFace, GitHub, etc.)
     */
    val url: String,
    /**
     * The framework this model is compatible with.
     * Strongly typed - uses InferenceFramework enum.
     */
    val framework: InferenceFramework,
    /**
     * The modality/capability this model provides (STT, TTS, text-to-text, etc.)
     * Strongly typed - uses FrameworkModality enum.
     */
    val modality: FrameworkModality,
    /**
     * Model format (auto-detected from URL if null)
     */
    val format: ModelFormat? = null,
    /**
     * Estimated memory requirement in bytes (optional)
     */
    val memoryRequirement: Long? = null,
    /**
     * Maximum context length for LLM models (optional)
     */
    val contextLength: Int? = null,
) {
    /**
     * Convert this registration to a full ModelInfo for storage in the registry.
     * Matches iOS ModelRegistration.toModelInfo() method.
     */
    fun toModelInfo(): ModelInfo {
        val effectiveFormat = format ?: ModelFormat.detectFromURL(url)

        return ModelInfo(
            id = id,
            name = name,
            category = ModelCategory.from(modality),
            format = effectiveFormat,
            downloadURL = url,
            localPath = null,
            downloadSize = memoryRequirement,
            memoryRequired = memoryRequirement,
            compatibleFrameworks = listOf(framework),
            preferredFramework = framework,
            contextLength = contextLength,
            supportsThinking = false,
            metadata =
                ModelInfoMetadata(
                    tags = listOf("registered"),
                    description = "Model registered via ModelRegistration",
                ),
        )
    }

    companion object {
        /**
         * Create a ModelRegistration with auto-generated ID and name from URL.
         * Matches iOS convenience initializer pattern.
         *
         * @param url URL to download the model from
         * @param framework The framework this model is compatible with
         * @param modality The modality/capability this model provides
         * @param id Optional ID (auto-generated from URL if null)
         * @param name Optional name (auto-generated from URL if null)
         * @param format Optional format (auto-detected from URL if null)
         * @param memoryRequirement Optional memory requirement in bytes
         * @param contextLength Optional context length for LLM models
         */
        fun create(
            url: String,
            framework: InferenceFramework,
            modality: FrameworkModality,
            id: String? = null,
            name: String? = null,
            format: ModelFormat? = null,
            memoryRequirement: Long? = null,
            contextLength: Int? = null,
        ): ModelRegistration {
            // Auto-generate ID from URL if not provided
            val effectiveId =
                id ?: url
                    .substringAfterLast("/")
                    .replace(".", "_")
                    .replace("-", "_")
                    .lowercase()

            // Auto-generate name from URL if not provided
            val effectiveName = name ?: url.substringAfterLast("/")

            return ModelRegistration(
                id = effectiveId,
                name = effectiveName,
                url = url,
                framework = framework,
                modality = modality,
                format = format,
                memoryRequirement = memoryRequirement,
                contextLength = contextLength,
            )
        }
    }
}
