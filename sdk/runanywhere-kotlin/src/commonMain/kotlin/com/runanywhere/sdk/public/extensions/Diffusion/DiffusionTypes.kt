/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for diffusion image generation.
 * Mirrors Swift sdk/runanywhere-swift/.../Diffusion/DiffusionTypes.swift.
 *
 * NOTE: As of v3.x the Kotlin/Android SDK does not yet ship a diffusion
 * runtime — the public surface is here so callers can write platform-
 * agnostic code that targets the same shape as the Swift/iOS SDK; the
 * runtime functions throw SDKError.unsupportedOperation on JVM/Android
 * until the C++ commons exposes the diffusion ABI on those platforms.
 */

package com.runanywhere.sdk.public.extensions.Diffusion

import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent

// =============================================================================
// DIFFUSION TOKENIZER SOURCE
// =============================================================================

/**
 * Tokenizer source for Stable Diffusion models. Apple's compiled CoreML
 * models don't include tokenizer files, so they must be downloaded
 * separately. This specifies which HuggingFace repository to download
 * them from.
 */
sealed class DiffusionTokenizerSource {
    /** Stable Diffusion 1.x tokenizer (CLIP ViT-L/14). */
    data object Sd15 : DiffusionTokenizerSource()

    /** Stable Diffusion 2.x tokenizer (OpenCLIP ViT-H/14). */
    data object Sd2 : DiffusionTokenizerSource()

    /** Stable Diffusion XL tokenizer (dual tokenizers). */
    data object Sdxl : DiffusionTokenizerSource()

    /**
     * Custom tokenizer from a specified base URL. The URL should point at
     * a directory containing `merges.txt` and `vocab.json`.
     */
    data class Custom(val customBaseUrl: String) : DiffusionTokenizerSource()

    /** The base URL for downloading tokenizer files. */
    val baseUrl: String
        get() =
            when (this) {
                Sd15 -> "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer"
                Sd2 -> "https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer"
                Sdxl -> "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer"
                is Custom -> customBaseUrl
            }

    /** Human-readable description. */
    val description: String
        get() =
            when (this) {
                Sd15 -> "Stable Diffusion 1.5 (CLIP)"
                Sd2 -> "Stable Diffusion 2.x (OpenCLIP)"
                Sdxl -> "Stable Diffusion XL"
                is Custom -> "Custom ($customBaseUrl)"
            }
}

// =============================================================================
// DIFFUSION MODEL VARIANT
// =============================================================================

/**
 * Stable Diffusion model variants.
 *
 * Hardware acceleration:
 * - iOS/macOS: CoreML Execution Provider (ANE -> GPU -> CPU)
 * - Android: NNAPI Execution Provider (NPU -> DSP -> GPU -> CPU)
 * - Desktop: optimized CPU with SIMD
 *
 * Fast models (no CFG, ~2x faster):
 * - SDXS: ultra-fast 1-step
 * - SDXL_TURBO: 4-step
 * - LCM: Latent Consistency Model, 4 steps
 */
enum class DiffusionModelVariant(val rawValue: String) {
    /** Stable Diffusion 1.5 (512x512 default). */
    SD15("sd15"),

    /** Stable Diffusion 2.1 (768x768 default). */
    SD21("sd21"),

    /** SDXL (1024x1024 default, requires 8GB+ RAM). */
    SDXL("sdxl"),

    /** SDXL Turbo — fast 4-step, no CFG needed. */
    SDXL_TURBO("sdxl_turbo"),

    /** SDXS — ultra-fast 1-step, no CFG needed. */
    SDXS("sdxs"),

    /** LCM (Latent Consistency Model) — fast 4-step with low CFG. */
    LCM("lcm"),
    ;

    /** Default resolution for this variant. */
    val defaultResolution: Pair<Int, Int>
        get() =
            when (this) {
                SD15, SDXS, LCM -> 512 to 512
                SD21 -> 768 to 768
                SDXL, SDXL_TURBO -> 1024 to 1024
            }

    /** Default number of inference steps. */
    val defaultSteps: Int
        get() =
            when (this) {
                SDXS -> 1
                SDXL_TURBO, LCM -> 4
                SD15, SD21, SDXL -> 20
            }

    /** Default classifier-free guidance scale. */
    val defaultGuidanceScale: Float
        get() =
            when (this) {
                SDXS, SDXL_TURBO -> 0.0f
                LCM -> 1.5f
                SD15, SD21, SDXL -> 7.5f
            }

    /** Whether this model requires classifier-free guidance (CFG). */
    val requiresCfg: Boolean
        get() =
            when (this) {
                SDXS, SDXL_TURBO -> false
                SD15, SD21, SDXL, LCM -> true
            }

    /** Default tokenizer source for this model variant. */
    val defaultTokenizerSource: DiffusionTokenizerSource
        get() =
            when (this) {
                SD15, SDXS, LCM -> DiffusionTokenizerSource.Sd15
                SD21 -> DiffusionTokenizerSource.Sd2
                SDXL, SDXL_TURBO -> DiffusionTokenizerSource.Sdxl
            }
}

// =============================================================================
// DIFFUSION SCHEDULER
// =============================================================================

/** Diffusion scheduler/sampler types for the denoising process. */
enum class DiffusionScheduler(val rawValue: String) {
    /** DPM++ 2M Karras — recommended for best quality/speed tradeoff. */
    DPM_PP_2M_KARRAS("dpm++_2m_karras"),

    /** DPM++ 2M. */
    DPM_PP_2M("dpm++_2m"),

    /** DPM++ 2M SDE. */
    DPM_PP_2M_SDE("dpm++_2m_sde"),

    /** DDIM. */
    DDIM("ddim"),

    /** Euler. */
    EULER("euler"),

    /** Euler Ancestral. */
    EULER_ANCESTRAL("euler_a"),

    /** PNDM. */
    PNDM("pndm"),

    /** LMS. */
    LMS("lms"),
    ;
}

// =============================================================================
// DIFFUSION MODE
// =============================================================================

/** Generation mode for diffusion. */
enum class DiffusionMode(val rawValue: String) {
    /** Generate image from text prompt. */
    TEXT_TO_IMAGE("txt2img"),

    /** Transform input image with prompt. */
    IMAGE_TO_IMAGE("img2img"),

    /** Edit specific regions with mask. */
    INPAINTING("inpainting"),
    ;
}

// =============================================================================
// DIFFUSION CONFIGURATION
// =============================================================================

/** Configuration for the diffusion component. */
data class DiffusionConfiguration(
    override val modelId: String? = null,
    val modelVariant: DiffusionModelVariant = DiffusionModelVariant.SD15,
    /** Enable safety checker for NSFW content filtering. */
    val enableSafetyChecker: Boolean = true,
    /** Reduce memory footprint (may reduce quality). */
    val reduceMemory: Boolean = false,
    override val preferredFramework: InferenceFramework? = null,
    /**
     * Tokenizer source for downloading missing tokenizer files. If null,
     * defaults to the tokenizer matching the model variant.
     */
    val tokenizerSource: DiffusionTokenizerSource? = null,
) : ComponentConfiguration {
    val componentType: SDKComponent get() = SDKComponent.LLM // Reused — Kotlin lacks DIFFUSION component constant.

    /** The effective tokenizer source (uses model variant default if not specified). */
    val effectiveTokenizerSource: DiffusionTokenizerSource
        get() = tokenizerSource ?: modelVariant.defaultTokenizerSource
}

// =============================================================================
// DIFFUSION GENERATION OPTIONS
// =============================================================================

/** Options for image generation. */
data class DiffusionGenerationOptions(
    /** Text prompt describing the desired image. */
    val prompt: String,
    /** Negative prompt — things to avoid in the image. */
    val negativePrompt: String = "",
    /** Output image width in pixels. */
    val width: Int = 512,
    /** Output image height in pixels. */
    val height: Int = 512,
    /** Number of denoising steps (10–50, default 28). */
    val steps: Int = 28,
    /** Classifier-free guidance scale (1.0–20.0, default 7.5). */
    val guidanceScale: Float = 7.5f,
    /** Random seed for reproducibility (-1 for random). */
    val seed: Long = -1L,
    /** Scheduler/sampler algorithm. */
    val scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,
    /** Generation mode. */
    val mode: DiffusionMode = DiffusionMode.TEXT_TO_IMAGE,
    /** Input image data for img2img/inpainting (PNG/JPEG bytes). */
    val inputImage: ByteArray? = null,
    /** Mask image data for inpainting (grayscale PNG bytes). */
    val maskImage: ByteArray? = null,
    /** Denoising strength for img2img (0.0–1.0). */
    val denoiseStrength: Float = 0.75f,
    /** Report intermediate images during generation. */
    val reportIntermediateImages: Boolean = false,
    /** Report progress every N steps. */
    val progressStride: Int = 1,
) {
    companion object {
        /** Helper for text-to-image generation. */
        fun textToImage(
            prompt: String,
            negativePrompt: String = "",
            width: Int = 512,
            height: Int = 512,
            steps: Int = 28,
            guidanceScale: Float = 7.5f,
            seed: Long = -1L,
            scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,
        ): DiffusionGenerationOptions =
            DiffusionGenerationOptions(
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

        /** Helper for image-to-image generation. */
        fun imageToImage(
            prompt: String,
            inputImage: ByteArray,
            negativePrompt: String = "",
            denoiseStrength: Float = 0.75f,
            steps: Int = 28,
            guidanceScale: Float = 7.5f,
            seed: Long = -1L,
            scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,
        ): DiffusionGenerationOptions =
            DiffusionGenerationOptions(
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

        /** Helper for inpainting. */
        fun inpainting(
            prompt: String,
            inputImage: ByteArray,
            maskImage: ByteArray,
            negativePrompt: String = "",
            steps: Int = 28,
            guidanceScale: Float = 7.5f,
            seed: Long = -1L,
            scheduler: DiffusionScheduler = DiffusionScheduler.DPM_PP_2M_KARRAS,
        ): DiffusionGenerationOptions =
            DiffusionGenerationOptions(
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
}

// =============================================================================
// DIFFUSION PROGRESS
// =============================================================================

/** Progress update during image generation. */
data class DiffusionProgress(
    /** Progress percentage (0.0–1.0). */
    val progress: Float,
    /** Current step number (1-based). */
    val currentStep: Int,
    /** Total number of steps. */
    val totalSteps: Int,
    /** Current stage description. */
    val stage: String,
    /** Intermediate image data (PNG, available if requested). */
    val intermediateImage: ByteArray? = null,
)

// =============================================================================
// DIFFUSION RESULT
// =============================================================================

/** Result of image generation. */
data class DiffusionResult(
    /** Generated image data (PNG format). */
    val imageData: ByteArray,
    /** Image width in pixels. */
    val width: Int,
    /** Image height in pixels. */
    val height: Int,
    /** Seed used for generation (for reproducibility). */
    val seedUsed: Long,
    /** Total generation time in milliseconds. */
    val generationTimeMs: Long,
    /** Whether the image was flagged by safety checker. */
    val safetyFlagged: Boolean = false,
)

// =============================================================================
// DIFFUSION CAPABILITIES
// =============================================================================

/**
 * Bit-flag set describing what the loaded diffusion model supports.
 * Mirrors Swift's `DiffusionCapabilities: OptionSet`.
 */
data class DiffusionCapabilities(val rawValue: UInt) {
    /** Supports text-to-image generation. */
    val supportsTextToImage: Boolean get() = (rawValue and 0x01u) != 0u

    /** Supports image-to-image transformation. */
    val supportsImageToImage: Boolean get() = (rawValue and 0x02u) != 0u

    /** Supports inpainting. */
    val supportsInpainting: Boolean get() = (rawValue and 0x04u) != 0u

    /** Supports streaming intermediate images. */
    val supportsIntermediateImages: Boolean get() = (rawValue and 0x08u) != 0u

    /** Has a built-in safety checker. */
    val supportsSafetyChecker: Boolean get() = (rawValue and 0x10u) != 0u

    companion object {
        val None = DiffusionCapabilities(0u)
        val TextToImage = DiffusionCapabilities(0x01u)
        val ImageToImage = DiffusionCapabilities(0x02u)
        val Inpainting = DiffusionCapabilities(0x04u)
        val IntermediateImages = DiffusionCapabilities(0x08u)
        val SafetyChecker = DiffusionCapabilities(0x10u)
    }
}
