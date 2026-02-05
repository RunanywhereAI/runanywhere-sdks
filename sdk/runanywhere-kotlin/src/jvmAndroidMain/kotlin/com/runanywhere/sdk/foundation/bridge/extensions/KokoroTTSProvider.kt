/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Provider interface for Kokoro TTS backend.
 * Allows the ONNX module to register its Kokoro implementation
 * without requiring the main SDK to depend on ONNX Runtime.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Result from Kokoro TTS synthesis.
 */
data class KokoroSynthesisResult(
    /** Audio samples as Float32 PCM */
    val samples: FloatArray,
    /** Sample rate in Hz (typically 24000) */
    val sampleRate: Int,
    /** Duration in seconds */
    val durationSeconds: Float,
    /** Inference time in milliseconds */
    val inferenceTimeMs: Long,
    /** Whether NPU was used */
    val usedNpu: Boolean
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as KokoroSynthesisResult
        return samples.contentEquals(other.samples) && sampleRate == other.sampleRate
    }

    override fun hashCode(): Int {
        var result = samples.contentHashCode()
        result = 31 * result + sampleRate
        return result
    }
}

/**
 * Provider interface for Kokoro TTS.
 * 
 * Implemented by the ONNX module's KokoroQnnTTS wrapper on Android.
 * This abstraction allows the main SDK to use Kokoro without directly
 * depending on ONNX Runtime or Android-specific code.
 */
interface KokoroTTSProvider {
    /**
     * Check if this provider can handle the given model.
     */
    fun canHandle(modelId: String, modelName: String?): Boolean
    
    /**
     * Load a Kokoro model.
     * 
     * @param modelPath Path to the model directory
     * @param modelId Model identifier
     * @return Result indicating success or failure
     */
    suspend fun loadModel(modelPath: String, modelId: String): Result<Unit>
    
    /**
     * Synthesize speech from text.
     * 
     * @param text Text to synthesize
     * @param voice Voice ID (e.g., "af_bella")
     * @param speed Speed multiplier (0.5 to 2.0)
     * @return Result containing audio data
     */
    suspend fun synthesize(
        text: String,
        voice: String = "af_bella",
        speed: Float = 1.0f
    ): Result<KokoroSynthesisResult>
    
    /**
     * List available voices.
     */
    fun listVoices(): List<String>
    
    /**
     * Check if a model is currently loaded.
     */
    val isLoaded: Boolean
    
    /**
     * Get the currently loaded model ID.
     */
    val loadedModelId: String?
    
    /**
     * Unload the current model and release resources.
     */
    fun unload()
}

/**
 * Registry for Kokoro TTS providers.
 * 
 * The ONNX module registers its KokoroQnnTTS-based provider here
 * when running on Android. On JVM (desktop), no provider is registered
 * and the SDK falls back to CppBridgeTTS.
 */
object KokoroTTSRegistry {
    private const val TAG = "KokoroTTSRegistry"
    private val logger = SDKLogger(TAG)
    
    @Volatile
    private var _provider: KokoroTTSProvider? = null
    
    /**
     * Get the registered Kokoro TTS provider, if any.
     */
    val provider: KokoroTTSProvider?
        get() = _provider
    
    /**
     * Check if a Kokoro provider is registered.
     */
    val hasProvider: Boolean
        get() = _provider != null
    
    /**
     * Register a Kokoro TTS provider.
     * Called by the ONNX module during initialization on Android.
     */
    fun register(provider: KokoroTTSProvider) {
        logger.info("Registering Kokoro TTS provider: ${provider::class.simpleName}")
        _provider = provider
    }
    
    /**
     * Unregister the current provider.
     */
    fun unregister() {
        _provider?.unload()
        _provider = null
        logger.info("Kokoro TTS provider unregistered")
    }
    
    /**
     * Check if the given model should use Kokoro backend.
     */
    fun shouldUseKokoro(modelId: String, modelName: String?): Boolean {
        val provider = _provider ?: return false
        return provider.canHandle(modelId, modelName)
    }
}
