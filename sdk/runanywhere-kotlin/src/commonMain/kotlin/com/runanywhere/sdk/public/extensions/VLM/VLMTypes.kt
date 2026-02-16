/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public types for VLM (Vision Language Model) operations.
 * These are thin wrappers over C++ types in rac_vlm_types.h
 *
 * Mirrors Swift VLMTypes.swift exactly.
 */

package com.runanywhere.sdk.public.extensions.VLM

import com.runanywhere.sdk.core.types.ComponentConfiguration
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.Serializable

// MARK: - VLM Image Format

/**
 * VLM image input format.
 * Mirrors C++ rac_vlm_image_format_t exactly.
 */
enum class VLMImageFormat(val rawValue: Int) {
    /** Path to image file (JPEG, PNG, etc.) */
    FILE_PATH(0),

    /** Raw RGB pixel buffer (RGBRGBRGB...) */
    RGB_PIXELS(1),

    /** Base64-encoded image data */
    BASE64(2),
}

// MARK: - VLM Image

/**
 * VLM image input structure.
 * Mirrors C++ rac_vlm_image_t and Swift VLMImage.
 *
 * Supports three input formats: file path, raw RGB pixels, or base64.
 */
data class VLMImage(
    val format: VLMImageFormat,
    val filePath: String? = null,
    val pixelData: ByteArray? = null,
    val base64Data: String? = null,
    val width: Int = 0,
    val height: Int = 0,
) {
    companion object {
        /** Create from a file path */
        fun fromFilePath(path: String): VLMImage =
            VLMImage(format = VLMImageFormat.FILE_PATH, filePath = path)

        /** Create from raw RGB pixel data */
        fun fromRGBPixels(data: ByteArray, width: Int, height: Int): VLMImage =
            VLMImage(
                format = VLMImageFormat.RGB_PIXELS,
                pixelData = data,
                width = width,
                height = height,
            )

        /** Create from base64-encoded image data */
        fun fromBase64(data: String): VLMImage =
            VLMImage(format = VLMImageFormat.BASE64, base64Data = data)
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is VLMImage) return false
        return format == other.format &&
            filePath == other.filePath &&
            (pixelData contentEquals other.pixelData) &&
            base64Data == other.base64Data &&
            width == other.width &&
            height == other.height
    }

    override fun hashCode(): Int {
        var result = format.hashCode()
        result = 31 * result + (filePath?.hashCode() ?: 0)
        result = 31 * result + (pixelData?.contentHashCode() ?: 0)
        result = 31 * result + (base64Data?.hashCode() ?: 0)
        result = 31 * result + width
        result = 31 * result + height
        return result
    }
}

// MARK: - VLM Generation Options

/**
 * Options for VLM image processing / text generation.
 * Mirrors C++ rac_vlm_options_t and Swift VLM generation options.
 */
@Serializable
data class VLMGenerationOptions(
    val maxTokens: Int = 2048,
    val temperature: Float = 0.7f,
    val topP: Float = 0.9f,
    val systemPrompt: String? = null,
    val maxImageSize: Int = 0,
    val nThreads: Int = 0,
    val useGpu: Boolean = true,
)

// MARK: - VLM Result

/**
 * Result of a VLM processing request.
 * Mirrors C++ rac_vlm_result_t and Swift VLMResult exactly.
 */
@Serializable
data class VLMResult(
    /** Generated text */
    val text: String,
    /** Number of tokens in prompt (including text tokens) */
    val promptTokens: Int = 0,
    /** Number of vision/image tokens specifically */
    val imageTokens: Int = 0,
    /** Number of tokens generated */
    val completionTokens: Int = 0,
    /** Total tokens (prompt + completion) */
    val totalTokens: Int = 0,
    /** Time to first token in milliseconds */
    val timeToFirstTokenMs: Long = 0,
    /** Time spent encoding the image in milliseconds */
    val imageEncodeTimeMs: Long = 0,
    /** Total generation time in milliseconds */
    val totalTimeMs: Long = 0,
    /** Tokens generated per second */
    val tokensPerSecond: Float = 0.0f,
)

// MARK: - VLM Streaming Result

/**
 * Container for streaming VLM generation with metrics.
 * Mirrors Swift VLMStreamingResult.
 *
 * In Kotlin, we use Flow instead of AsyncThrowingStream.
 */
data class VLMStreamingResult(
    /** Flow of tokens as they are generated */
    val stream: Flow<String>,
    /** Deferred result that completes with final generation result including metrics */
    val result: Deferred<VLMResult>,
)

// MARK: - VLM Configuration

/**
 * Configuration for VLM component.
 * Mirrors C++ rac_vlm_config_t.
 */
@Serializable
data class VLMConfiguration(
    override val modelId: String? = null,
    val contextLength: Int = 4096,
    val temperature: Float = 0.7f,
    val maxTokens: Int = 2048,
    val systemPrompt: String? = null,
    val streamingEnabled: Boolean = true,
    override val preferredFramework: InferenceFramework? = null,
) : ComponentConfiguration {
    val componentType: SDKComponent get() = SDKComponent.VLM

    fun validate() {
        require(contextLength in 1..32768) {
            "Context length must be between 1 and 32768"
        }
        require(temperature in 0.0f..2.0f) {
            "Temperature must be between 0 and 2.0"
        }
        require(maxTokens in 1..contextLength) {
            "Max tokens must be between 1 and context length"
        }
    }
}
