/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for diffusion image generation.
 * These are thin wrappers over C++ types in rac_diffusion_types.h.
 * All business logic (scheduling, model loading, inference) is in C++.
 *
 * Mirrors Swift DiffusionTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.Diffusion

import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import kotlinx.serialization.Serializable

// MARK: - Model Variant

/**
 * Stable Diffusion model variants with different capabilities and defaults.
 * Maps to rac_diffusion_model_variant_t in C++.
 */
@Serializable
enum class DiffusionModelVariant(
    val rawValue: Int,
) {
    SD_1_5(0),
    SD_2_1(1),
    SDXL(2),
    SDXL_TURBO(3),
    SDXS(4),
    LCM(5),
    ;

    /** Default image resolution for this variant */
    val defaultWidth: Int
        get() = when (this) {
            SD_1_5, SDXS, LCM -> 512
            SD_2_1 -> 768
            SDXL, SDXL_TURBO -> 1024
        }

    val defaultHeight: Int get() = defaultWidth

    /** Default denoising steps */
    val defaultSteps: Int
        get() = when (this) {
            SD_1_5, SD_2_1, SDXL -> 20
            SDXL_TURBO, LCM -> 4
            SDXS -> 1
        }

    /** Default guidance scale */
    val defaultGuidanceScale: Float
        get() = when (this) {
            SD_1_5, SD_2_1, SDXL -> 7.5f
            SDXL_TURBO, SDXS -> 0.0f
            LCM -> 1.5f
        }

    /** Whether this variant requires classifier-free guidance */
    val requiresCFG: Boolean
        get() = when (this) {
            SDXL_TURBO, SDXS -> false
            else -> true
        }

    /** Default tokenizer source for this variant */
    val defaultTokenizerSource: DiffusionTokenizerSource
        get() = when (this) {
            SD_1_5, SDXS, LCM -> DiffusionTokenizerSource.SD_1_5
            SD_2_1 -> DiffusionTokenizerSource.SD_2_X
            SDXL, SDXL_TURBO -> DiffusionTokenizerSource.SDXL
        }

    val displayName: String
        get() = when (this) {
            SD_1_5 -> "Stable Diffusion 1.5"
            SD_2_1 -> "Stable Diffusion 2.1"
            SDXL -> "SDXL"
            SDXL_TURBO -> "SDXL Turbo"
            SDXS -> "SDXS"
            LCM -> "LCM"
        }

    companion object {
        fun fromRawValue(value: Int): DiffusionModelVariant? =
            entries.find { it.rawValue == value }
    }
}

// MARK: - Tokenizer Source

/**
 * Predefined HuggingFace tokenizer sources.
 * Maps to rac_diffusion_tokenizer_source_t in C++.
 */
@Serializable
enum class DiffusionTokenizerSource(
    val rawValue: Int,
) {
    SD_1_5(0),
    SD_2_X(1),
    SDXL(2),
    CUSTOM(99),
    ;

    companion object {
        fun fromRawValue(value: Int): DiffusionTokenizerSource? =
            entries.find { it.rawValue == value }
    }
}

// MARK: - Scheduler

/**
 * Diffusion scheduler/sampler algorithms for the denoising process.
 * Maps to rac_diffusion_scheduler_t in C++.
 */
@Serializable
enum class DiffusionScheduler(
    val rawValue: Int,
) {
    DPM_PP_2M_KARRAS(0),
    DPM_PP_2M(1),
    DPM_PP_2M_SDE(2),
    DDIM(3),
    EULER(4),
    EULER_ANCESTRAL(5),
    PNDM(6),
    LMS(7),
    ;

    val displayName: String
        get() = when (this) {
            DPM_PP_2M_KARRAS -> "DPM++ 2M Karras"
            DPM_PP_2M -> "DPM++ 2M"
            DPM_PP_2M_SDE -> "DPM++ 2M SDE"
            DDIM -> "DDIM"
            EULER -> "Euler"
            EULER_ANCESTRAL -> "Euler Ancestral"
            PNDM -> "PNDM"
            LMS -> "LMS"
        }

    companion object {
        fun fromRawValue(value: Int): DiffusionScheduler? =
            entries.find { it.rawValue == value }
    }
}

// MARK: - Generation Mode

/**
 * Image generation mode.
 * Maps to rac_diffusion_mode_t in C++.
 */
@Serializable
enum class DiffusionMode(
    val rawValue: Int,
) {
    TEXT_TO_IMAGE(0),
    IMAGE_TO_IMAGE(1),
    INPAINTING(2),
    ;

    companion object {
        fun fromRawValue(value: Int): DiffusionMode? =
            entries.find { it.rawValue == value }
    }
}

// MARK: - Configuration

/**
 * Configuration for the diffusion component.
 * Mirrors Swift DiffusionConfiguration exactly.
 */
@Serializable
data class DiffusionConfiguration(
    override val modelId: String? = null,
    override val preferredFramework: InferenceFramework? = null,
    val modelVariant: DiffusionModelVariant = DiffusionModelVariant.SD_1_5,
    val enableSafetyChecker: Boolean = true,
    val reduceMemory: Boolean = false,
    val tokenizerSource: DiffusionTokenizerSource? = null,
) : ComponentConfiguration {
    val componentType: SDKComponent get() = SDKComponent.DIFFUSION

    fun validate() {
        // No strict validation needed - C++ handles model-specific constraints
    }

    /** Convert to JSON for JNI bridge. */
    fun toJson(): String {
        val sb = StringBuilder("{")
        sb.append("\"model_variant\":${modelVariant.rawValue}")
        sb.append(",\"enable_safety_checker\":$enableSafetyChecker")
        sb.append(",\"reduce_memory\":$reduceMemory")
        preferredFramework?.let {
            val frameworkId = when (it) {
                InferenceFramework.COREML -> 8
                InferenceFramework.SDCPP -> 9
                else -> 99
            }
            sb.append(",\"preferred_framework\":$frameworkId")
        }
        sb.append("}")
        return sb.toString()
    }
}

// MARK: - Generation Options

/**
 * Options for controlling image generation.
 * Mirrors Swift DiffusionGenerationOptions exactly.
 */
@Serializable
data class DiffusionGenerationOptions(
    val prompt: String,
    val negativePrompt: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val steps: Int? = null,
    val guidanceScale: Float? = null,
    val seed: Long = -1,
    val scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,
    val mode: DiffusionMode = DiffusionMode.TEXT_TO_IMAGE,
    val inputImage: ByteArray? = null,
    val inputImageWidth: Int = 0,
    val inputImageHeight: Int = 0,
    val maskImage: ByteArray? = null,
    val denoiseStrength: Float = 0.75f,
    val reportIntermediateImages: Boolean = false,
    val progressStride: Int = 1,
) {
    /** Convert to JSON for JNI bridge (excluding binary data). */
    fun toJson(): String {
        val sb = StringBuilder("{")
        sb.append("\"prompt\":\"${prompt.replace("\"", "\\\"")}\"")
        negativePrompt?.let { sb.append(",\"negative_prompt\":\"${it.replace("\"", "\\\"")}\"") }
        width?.let { sb.append(",\"width\":$it") }
        height?.let { sb.append(",\"height\":$it") }
        steps?.let { sb.append(",\"steps\":$it") }
        guidanceScale?.let { sb.append(",\"guidance_scale\":$it") }
        sb.append(",\"seed\":$seed")
        sb.append(",\"scheduler\":${scheduler.rawValue}")
        sb.append(",\"mode\":${mode.rawValue}")
        sb.append(",\"denoise_strength\":$denoiseStrength")
        sb.append("}")
        return sb.toString()
    }

    companion object {
        /** Create options with defaults from model variant. */
        fun withVariantDefaults(
            prompt: String,
            variant: DiffusionModelVariant,
            negativePrompt: String? = null,
            seed: Long = -1,
        ): DiffusionGenerationOptions =
            DiffusionGenerationOptions(
                prompt = prompt,
                negativePrompt = negativePrompt,
                width = variant.defaultWidth,
                height = variant.defaultHeight,
                steps = variant.defaultSteps,
                guidanceScale = variant.defaultGuidanceScale,
                seed = seed,
            )
    }
}

// MARK: - Progress

/**
 * Reports progress during image generation.
 * Mirrors Swift DiffusionProgress exactly.
 */
data class DiffusionProgress(
    /** Progress percentage (0.0 - 1.0) */
    val progress: Float,
    /** Current step number (1-based) */
    val currentStep: Int,
    /** Total number of steps */
    val totalSteps: Int,
    /** Current stage description */
    val stage: String,
    /** Intermediate image RGBA data (null if not requested) */
    val intermediateImage: ByteArray? = null,
    val intermediateImageWidth: Int = 0,
    val intermediateImageHeight: Int = 0,
)

// MARK: - Result

/**
 * Contains the generated image and metadata.
 * Mirrors Swift DiffusionResult exactly.
 */
data class DiffusionResult(
    /** Generated image RGBA data */
    val imageData: ByteArray,
    /** Image width in pixels */
    val width: Int,
    /** Image height in pixels */
    val height: Int,
    /** Seed used for generation (useful for reproducibility) */
    val seedUsed: Long,
    /** Total generation time in milliseconds */
    val generationTimeMs: Long,
    /** Whether the image was flagged by safety checker */
    val safetyFlagged: Boolean = false,
)

// MARK: - Capabilities

/**
 * Capability flags for the diffusion backend.
 * Maps to RAC_DIFFUSION_CAP_* in C++.
 */
object DiffusionCapabilities {
    const val TEXT_TO_IMAGE = 1 shl 0
    const val IMAGE_TO_IMAGE = 1 shl 1
    const val INPAINTING = 1 shl 2
    const val INTERMEDIATE_IMAGES = 1 shl 3
    const val SAFETY_CHECKER = 1 shl 4

    fun supportsTextToImage(caps: Int): Boolean = (caps and TEXT_TO_IMAGE) != 0
    fun supportsImageToImage(caps: Int): Boolean = (caps and IMAGE_TO_IMAGE) != 0
    fun supportsInpainting(caps: Int): Boolean = (caps and INPAINTING) != 0
}

// MARK: - Info

/**
 * Information about the loaded diffusion service.
 * Mirrors Swift DiffusionInfo exactly.
 */
data class DiffusionInfo(
    val isReady: Boolean,
    val modelVariant: DiffusionModelVariant,
    val supportsTextToImage: Boolean,
    val supportsImageToImage: Boolean,
    val supportsInpainting: Boolean,
    val safetyCheckerEnabled: Boolean,
    val maxWidth: Int,
    val maxHeight: Int,
)

// MARK: - Error Codes

/**
 * Diffusion-specific error codes.
 */
enum class DiffusionErrorCode {
    MODEL_NOT_LOADED,
    INVALID_PROMPT,
    GENERATION_FAILED,
    CANCELLED,
    OUT_OF_MEMORY,
    UNSUPPORTED_MODEL,
    SAFETY_CHECK_FAILED,
}
