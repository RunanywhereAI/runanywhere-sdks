/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for Diffusion image generation.
 * These are thin wrappers over C++ types in rac_diffusion_types.h
 *
 * Mirrors Swift DiffusionTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.Diffusion

import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.ComponentOutput
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import kotlinx.serialization.Serializable

// MARK: - Diffusion Tokenizer Source

/**
 * Tokenizer source for Stable Diffusion models.
 * Apple's compiled CoreML models don't include tokenizer files, so they must be downloaded separately.
 * This specifies which HuggingFace repository to download them from.
 *
 * Mirrors Swift DiffusionTokenizerSource exactly.
 */
sealed class DiffusionTokenizerSource {
    /** Stable Diffusion 1.x tokenizer (CLIP ViT-L/14) */
    data object SD15 : DiffusionTokenizerSource()

    /** Stable Diffusion 2.x tokenizer (OpenCLIP ViT-H/14) */
    data object SD2 : DiffusionTokenizerSource()

    /** Stable Diffusion XL tokenizer (dual tokenizers) */
    data object SDXL : DiffusionTokenizerSource()

    /** Custom tokenizer from a specified base URL */
    data class Custom(val baseURL: String) : DiffusionTokenizerSource()

    /** The base URL for downloading tokenizer files */
    val url: String
        get() = when (this) {
            is SD15 -> "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer"
            is SD2 -> "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer"
            is SDXL -> "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer"
            is Custom -> baseURL
        }

    /** Human-readable description */
    val description: String
        get() = when (this) {
            is SD15 -> "Stable Diffusion 1.5 (CLIP)"
            is SD2 -> "Stable Diffusion 2.x (OpenCLIP)"
            is SDXL -> "Stable Diffusion XL"
            is Custom -> "Custom ($baseURL)"
        }

    /** C++ enum value (RAC_DIFFUSION_TOKENIZER_*) */
    val cValue: Int
        get() = when (this) {
            is SD15 -> 0  // RAC_DIFFUSION_TOKENIZER_SD_1_5
            is SD2 -> 1   // RAC_DIFFUSION_TOKENIZER_SD_2_X
            is SDXL -> 2  // RAC_DIFFUSION_TOKENIZER_SDXL
            is Custom -> 99 // RAC_DIFFUSION_TOKENIZER_CUSTOM
        }

    /** Custom URL (only for Custom case) */
    val customURL: String?
        get() = when (this) {
            is Custom -> baseURL
            else -> null
        }

    companion object {
        fun fromCValue(value: Int): DiffusionTokenizerSource = when (value) {
            0 -> SD15
            1 -> SD2
            2 -> SDXL
            else -> SD15
        }
    }
}

// MARK: - Diffusion Model Variant

/**
 * Stable Diffusion model variants.
 * Mirrors Swift DiffusionModelVariant exactly.
 */
@Serializable
enum class DiffusionModelVariant(
    val rawValue: String,
) {
    /** Stable Diffusion 1.5 (512x512 default) */
    SD15("sd15"),

    /** Stable Diffusion 2.1 (768x768 default) */
    SD21("sd21"),

    /** SDXL (1024x1024 default, requires 8GB+ RAM) */
    SDXL("sdxl"),

    /** SDXL Turbo (fast, fewer steps) */
    SDXL_TURBO("sdxl_turbo"),
    ;

    /** Default resolution for this variant */
    val defaultResolution: Pair<Int, Int>
        get() = when (this) {
            SD15 -> 512 to 512
            SD21 -> 768 to 768
            SDXL, SDXL_TURBO -> 1024 to 1024
        }

    /** Default width */
    val defaultWidth: Int get() = defaultResolution.first

    /** Default height */
    val defaultHeight: Int get() = defaultResolution.second

    /** Default number of steps for this variant */
    val defaultSteps: Int
        get() = when (this) {
            SD15, SD21, SDXL -> 28
            SDXL_TURBO -> 4
        }

    /** Default tokenizer source for this model variant */
    val defaultTokenizerSource: DiffusionTokenizerSource
        get() = when (this) {
            SD15 -> DiffusionTokenizerSource.SD15
            SD21 -> DiffusionTokenizerSource.SD2
            SDXL, SDXL_TURBO -> DiffusionTokenizerSource.SDXL
        }

    /** C++ enum value (RAC_DIFFUSION_MODEL_*) */
    val cValue: Int
        get() = when (this) {
            SD15 -> 0       // RAC_DIFFUSION_MODEL_SD_1_5
            SD21 -> 1       // RAC_DIFFUSION_MODEL_SD_2_1
            SDXL -> 2       // RAC_DIFFUSION_MODEL_SDXL
            SDXL_TURBO -> 3 // RAC_DIFFUSION_MODEL_SDXL_TURBO
        }

    companion object {
        fun fromRawValue(value: String): DiffusionModelVariant? =
            entries.find { it.rawValue.equals(value, ignoreCase = true) }

        fun fromCValue(value: Int): DiffusionModelVariant = when (value) {
            0 -> SD15
            1 -> SD21
            2 -> SDXL
            3 -> SDXL_TURBO
            else -> SD15
        }
    }
}

// MARK: - Diffusion Scheduler

/**
 * Diffusion scheduler/sampler types for the denoising process.
 * Mirrors Swift DiffusionScheduler exactly.
 */
@Serializable
enum class DiffusionScheduler(
    val rawValue: String,
) {
    /** DPM++ 2M Karras - Recommended for best quality/speed tradeoff */
    DPM_PP_2M_KARRAS("dpm++_2m_karras"),

    /** DPM++ 2M */
    DPM_PP_2M("dpm++_2m"),

    /** DPM++ 2M SDE */
    DPM_PP_2M_SDE("dpm++_2m_sde"),

    /** DDIM */
    DDIM("ddim"),

    /** Euler */
    EULER("euler"),

    /** Euler Ancestral */
    EULER_ANCESTRAL("euler_a"),

    /** PNDM */
    PNDM("pndm"),

    /** LMS */
    LMS("lms"),
    ;

    /** C++ enum value (RAC_DIFFUSION_SCHEDULER_*) */
    val cValue: Int
        get() = when (this) {
            DPM_PP_2M_KARRAS -> 0
            DPM_PP_2M -> 1
            DPM_PP_2M_SDE -> 2
            DDIM -> 3
            EULER -> 4
            EULER_ANCESTRAL -> 5
            PNDM -> 6
            LMS -> 7
        }

    companion object {
        fun fromRawValue(value: String): DiffusionScheduler? =
            entries.find { it.rawValue.equals(value, ignoreCase = true) }

        fun fromCValue(value: Int): DiffusionScheduler = when (value) {
            0 -> DPM_PP_2M_KARRAS
            1 -> DPM_PP_2M
            2 -> DPM_PP_2M_SDE
            3 -> DDIM
            4 -> EULER
            5 -> EULER_ANCESTRAL
            6 -> PNDM
            7 -> LMS
            else -> DPM_PP_2M_KARRAS
        }
    }
}

// MARK: - Diffusion Mode

/**
 * Generation mode for diffusion.
 * Mirrors Swift DiffusionMode exactly.
 */
@Serializable
enum class DiffusionMode(
    val rawValue: String,
) {
    /** Generate image from text prompt */
    TEXT_TO_IMAGE("txt2img"),

    /** Transform input image with prompt */
    IMAGE_TO_IMAGE("img2img"),

    /** Edit specific regions with mask */
    INPAINTING("inpainting"),
    ;

    /** C++ enum value (RAC_DIFFUSION_MODE_*) */
    val cValue: Int
        get() = when (this) {
            TEXT_TO_IMAGE -> 0
            IMAGE_TO_IMAGE -> 1
            INPAINTING -> 2
        }

    companion object {
        fun fromRawValue(value: String): DiffusionMode? =
            entries.find { it.rawValue.equals(value, ignoreCase = true) }

        fun fromCValue(value: Int): DiffusionMode = when (value) {
            0 -> TEXT_TO_IMAGE
            1 -> IMAGE_TO_IMAGE
            2 -> INPAINTING
            else -> TEXT_TO_IMAGE
        }
    }
}

// MARK: - Diffusion Configuration

/**
 * Configuration for the diffusion component.
 * Mirrors Swift DiffusionConfiguration exactly.
 */
@Serializable
data class DiffusionConfiguration(
    override val modelId: String? = null,
    val modelVariant: DiffusionModelVariant = DiffusionModelVariant.SD15,
    val enableSafetyChecker: Boolean = true,
    val reduceMemory: Boolean = false,
    override val preferredFramework: InferenceFramework? = null,
    // Note: tokenizerSource not serializable due to sealed class, handle separately
) : ComponentConfiguration {

    val componentType: SDKComponent get() = SDKComponent.DIFFUSION

    /** Transient tokenizer source (not serialized) */
    @kotlinx.serialization.Transient
    var tokenizerSource: DiffusionTokenizerSource? = null
        private set

    /** The effective tokenizer source (uses model variant default if not specified) */
    val effectiveTokenizerSource: DiffusionTokenizerSource
        get() = tokenizerSource ?: modelVariant.defaultTokenizerSource

    /** Validate the configuration */
    fun validate() {
        // Configuration is always valid - defaults are used
    }

    /** Builder for creating configurations with tokenizer source */
    class Builder(
        var modelId: String? = null,
        var modelVariant: DiffusionModelVariant = DiffusionModelVariant.SD15,
        var enableSafetyChecker: Boolean = true,
        var reduceMemory: Boolean = false,
        var preferredFramework: InferenceFramework? = null,
        var tokenizerSource: DiffusionTokenizerSource? = null,
    ) {
        fun build(): DiffusionConfiguration {
            val config = DiffusionConfiguration(
                modelId = modelId,
                modelVariant = modelVariant,
                enableSafetyChecker = enableSafetyChecker,
                reduceMemory = reduceMemory,
                preferredFramework = preferredFramework,
            )
            // Set tokenizer source via internal access
            config.tokenizerSource = tokenizerSource
            return config
        }
    }

    companion object {
        /** Create with builder */
        fun build(block: Builder.() -> Unit): DiffusionConfiguration {
            return Builder().apply(block).build()
        }

        /** Create with custom tokenizer URL */
        fun withCustomTokenizer(
            modelVariant: DiffusionModelVariant,
            tokenizerURL: String,
            modelId: String? = null,
            enableSafetyChecker: Boolean = true,
            reduceMemory: Boolean = false,
        ): DiffusionConfiguration = build {
            this.modelId = modelId
            this.modelVariant = modelVariant
            this.enableSafetyChecker = enableSafetyChecker
            this.reduceMemory = reduceMemory
            this.tokenizerSource = DiffusionTokenizerSource.Custom(tokenizerURL)
        }
    }
}

// MARK: - Diffusion Generation Options

/**
 * Options for image generation.
 * Mirrors Swift DiffusionGenerationOptions exactly.
 */
@Serializable
data class DiffusionGenerationOptions(
    /** Text prompt describing the desired image */
    val prompt: String,

    /** Negative prompt - things to avoid in the image */
    val negativePrompt: String = "",

    /** Output image width in pixels */
    val width: Int = 512,

    /** Output image height in pixels */
    val height: Int = 512,

    /** Number of denoising steps (10-50, default: 28) */
    val steps: Int = 28,

    /** Classifier-free guidance scale (1.0-20.0, default: 7.5) */
    val guidanceScale: Float = 7.5f,

    /** Random seed for reproducibility (-1 for random) */
    val seed: Long = -1L,

    /** Scheduler/sampler algorithm */
    val scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,

    /** Generation mode */
    val mode: DiffusionMode = DiffusionMode.TEXT_TO_IMAGE,

    /** Input image data for img2img/inpainting (PNG/JPEG bytes) */
    val inputImage: ByteArray? = null,

    /** Mask image data for inpainting (grayscale PNG bytes) */
    val maskImage: ByteArray? = null,

    /** Denoising strength for img2img (0.0-1.0) */
    val denoiseStrength: Float = 0.75f,

    /** Report intermediate images during generation */
    val reportIntermediateImages: Boolean = false,

    /** Report progress every N steps */
    val progressStride: Int = 1,
) {
    companion object {
        /** Create options for text-to-image generation */
        fun textToImage(
            prompt: String,
            negativePrompt: String = "",
            width: Int = 512,
            height: Int = 512,
            steps: Int = 28,
            guidanceScale: Float = 7.5f,
            seed: Long = -1L,
            scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,
        ): DiffusionGenerationOptions = DiffusionGenerationOptions(
            prompt = prompt,
            negativePrompt = negativePrompt,
            width = width,
            height = height,
            steps = steps,
            guidanceScale = guidanceScale,
            seed = seed,
            scheduler = scheduler,
            mode = DiffusionMode.TEXT_TO_IMAGE,
        )

        /** Create options for image-to-image transformation */
        fun imageToImage(
            prompt: String,
            inputImage: ByteArray,
            negativePrompt: String = "",
            denoiseStrength: Float = 0.75f,
            steps: Int = 28,
            guidanceScale: Float = 7.5f,
            seed: Long = -1L,
            scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,
        ): DiffusionGenerationOptions = DiffusionGenerationOptions(
            prompt = prompt,
            negativePrompt = negativePrompt,
            steps = steps,
            guidanceScale = guidanceScale,
            seed = seed,
            scheduler = scheduler,
            mode = DiffusionMode.IMAGE_TO_IMAGE,
            inputImage = inputImage,
            denoiseStrength = denoiseStrength,
        )

        /** Create options for inpainting */
        fun inpainting(
            prompt: String,
            inputImage: ByteArray,
            maskImage: ByteArray,
            negativePrompt: String = "",
            steps: Int = 28,
            guidanceScale: Float = 7.5f,
            seed: Long = -1L,
            scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,
        ): DiffusionGenerationOptions = DiffusionGenerationOptions(
            prompt = prompt,
            negativePrompt = negativePrompt,
            steps = steps,
            guidanceScale = guidanceScale,
            seed = seed,
            scheduler = scheduler,
            mode = DiffusionMode.INPAINTING,
            inputImage = inputImage,
            maskImage = maskImage,
        )
    }

    // ByteArray equality
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DiffusionGenerationOptions) return false
        return prompt == other.prompt &&
            negativePrompt == other.negativePrompt &&
            width == other.width &&
            height == other.height &&
            steps == other.steps &&
            guidanceScale == other.guidanceScale &&
            seed == other.seed &&
            scheduler == other.scheduler &&
            mode == other.mode &&
            inputImage.contentEquals(other.inputImage) &&
            maskImage.contentEquals(other.maskImage) &&
            denoiseStrength == other.denoiseStrength
    }

    override fun hashCode(): Int {
        var result = prompt.hashCode()
        result = 31 * result + negativePrompt.hashCode()
        result = 31 * result + width
        result = 31 * result + height
        result = 31 * result + steps
        result = 31 * result + guidanceScale.hashCode()
        result = 31 * result + seed.hashCode()
        result = 31 * result + scheduler.hashCode()
        result = 31 * result + mode.hashCode()
        result = 31 * result + (inputImage?.contentHashCode() ?: 0)
        result = 31 * result + (maskImage?.contentHashCode() ?: 0)
        result = 31 * result + denoiseStrength.hashCode()
        return result
    }
}

// MARK: - Diffusion Progress

/**
 * Progress update during image generation.
 * Mirrors Swift DiffusionProgress exactly.
 */
@Serializable
data class DiffusionProgress(
    /** Progress percentage (0.0 - 1.0) */
    val progress: Float,

    /** Current step number (1-based) */
    val currentStep: Int,

    /** Total number of steps */
    val totalSteps: Int,

    /** Current stage description */
    val stage: String,

    /** Intermediate image data (PNG, available if requested) */
    val intermediateImage: ByteArray? = null,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DiffusionProgress) return false
        return progress == other.progress &&
            currentStep == other.currentStep &&
            totalSteps == other.totalSteps &&
            stage == other.stage &&
            intermediateImage.contentEquals(other.intermediateImage)
    }

    override fun hashCode(): Int {
        var result = progress.hashCode()
        result = 31 * result + currentStep
        result = 31 * result + totalSteps
        result = 31 * result + stage.hashCode()
        result = 31 * result + (intermediateImage?.contentHashCode() ?: 0)
        return result
    }
}

// MARK: - Diffusion Result

/**
 * Result of image generation.
 * Mirrors Swift DiffusionResult exactly.
 */
@Serializable
data class DiffusionResult(
    /** Generated image data (PNG format) */
    val imageData: ByteArray,

    /** Image width in pixels */
    val width: Int,

    /** Image height in pixels */
    val height: Int,

    /** Seed used for generation (for reproducibility) */
    val seedUsed: Long,

    /** Total generation time in milliseconds */
    val generationTimeMs: Long,

    /** Whether the image was flagged by safety checker */
    val safetyFlagged: Boolean = false,

    /** Timestamp of result creation */
    override val timestamp: Long = System.currentTimeMillis(),
) : ComponentOutput {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DiffusionResult) return false
        return imageData.contentEquals(other.imageData) &&
            width == other.width &&
            height == other.height &&
            seedUsed == other.seedUsed &&
            generationTimeMs == other.generationTimeMs &&
            safetyFlagged == other.safetyFlagged
    }

    override fun hashCode(): Int {
        var result = imageData.contentHashCode()
        result = 31 * result + width
        result = 31 * result + height
        result = 31 * result + seedUsed.hashCode()
        result = 31 * result + generationTimeMs.hashCode()
        result = 31 * result + safetyFlagged.hashCode()
        return result
    }
}

// MARK: - Diffusion Error Codes

/**
 * Diffusion error codes.
 * Mirrors Swift SDKError.DiffusionErrorCode exactly.
 */
enum class DiffusionErrorCode(
    val rawValue: String,
) {
    NOT_INITIALIZED("diffusion_not_initialized"),
    MODEL_NOT_FOUND("diffusion_model_not_found"),
    MODEL_LOAD_FAILED("diffusion_model_load_failed"),
    INITIALIZATION_FAILED("diffusion_initialization_failed"),
    GENERATION_FAILED("diffusion_generation_failed"),
    CANCELLED("diffusion_cancelled"),
    INVALID_OPTIONS("diffusion_invalid_options"),
    UNSUPPORTED_MODE("diffusion_unsupported_mode"),
    OUT_OF_MEMORY("diffusion_out_of_memory"),
    SAFETY_CHECK_FAILED("diffusion_safety_check_failed"),
    CONFIGURATION_FAILED("diffusion_configuration_failed"),
    ;

    companion object {
        fun fromRawValue(value: String): DiffusionErrorCode? =
            entries.find { it.rawValue == value }
    }
}
