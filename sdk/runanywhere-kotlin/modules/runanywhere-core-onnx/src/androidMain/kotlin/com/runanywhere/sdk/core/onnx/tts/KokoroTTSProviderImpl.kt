/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Kokoro TTS Provider implementation for Android.
 * Wraps KokoroQnnTTS and registers with the SDK's KokoroTTSRegistry.
 */

package com.runanywhere.sdk.core.onnx.tts

import android.content.Context
import android.util.Log
import com.runanywhere.sdk.foundation.bridge.extensions.KokoroSynthesisResult
import com.runanywhere.sdk.foundation.bridge.extensions.KokoroTTSProvider
import com.runanywhere.sdk.foundation.bridge.extensions.KokoroTTSRegistry
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Implementation of KokoroTTSProvider that wraps KokoroQnnTTS.
 * 
 * This class bridges the ONNX module's Kokoro implementation
 * to the main SDK's TTS routing system.
 */
class KokoroTTSProviderImpl(
    private val context: Context
) : KokoroTTSProvider {
    
    companion object {
        private const val TAG = "KokoroTTSProviderImpl"
        
        /**
         * Register the Kokoro TTS provider with the SDK.
         * Call this after AndroidPlatformContext.initialize() and ONNX.register()
         */
        fun register(context: Context) {
            Log.i(TAG, "Registering Kokoro TTS provider")
            val provider = KokoroTTSProviderImpl(context.applicationContext)
            KokoroTTSRegistry.register(provider)
        }
        
        /**
         * Check if the given model should use Kokoro backend.
         */
        fun isKokoroModel(modelId: String, modelName: String?): Boolean {
            return modelId.contains("kokoro", ignoreCase = true) ||
                   modelName?.contains("kokoro", ignoreCase = true) == true
        }
    }
    
    private val mutex = Mutex()
    
    @Volatile
    private var _tts: KokoroQnnTTS? = null
    
    @Volatile
    private var _loadedModelId: String? = null
    
    override val isLoaded: Boolean
        get() = _tts != null
    
    override val loadedModelId: String?
        get() = _loadedModelId
    
    override fun canHandle(modelId: String, modelName: String?): Boolean {
        return isKokoroModel(modelId, modelName)
    }
    
    override suspend fun loadModel(modelPath: String, modelId: String): Result<Unit> {
        return mutex.withLock {
            Log.i(TAG, "Loading Kokoro model: $modelId from $modelPath")
            
            // Unload existing model if any
            _tts?.release()
            _tts = null
            _loadedModelId = null
            
            // Create new KokoroQnnTTS instance
            KokoroQnnTTS.create(context, modelPath, preferNpu = true).map { tts ->
                _tts = tts
                _loadedModelId = modelId
                Log.i(TAG, "Kokoro model loaded successfully: $modelId")
                Unit  // Explicitly return Unit
            }
        }
    }
    
    override suspend fun synthesize(
        text: String,
        voice: String,
        speed: Float
    ): Result<KokoroSynthesisResult> {
        val tts = _tts
            ?: return Result.failure(IllegalStateException("Kokoro TTS not loaded"))
        
        Log.d(TAG, "Synthesizing with Kokoro: text=\"${text.take(30)}...\", voice=$voice, speed=$speed")
        
        return tts.synthesize(text, voice, speed).map { result ->
            KokoroSynthesisResult(
                samples = result.samples,
                sampleRate = result.sampleRate,
                durationSeconds = result.durationSeconds,
                inferenceTimeMs = result.inferenceTimeMs,
                usedNpu = result.usedNpu
            )
        }
    }
    
    override fun listVoices(): List<String> {
        return _tts?.listVoices() ?: emptyList()
    }
    
    override fun unload() {
        Log.i(TAG, "Unloading Kokoro model: $_loadedModelId")
        _tts?.release()
        _tts = null
        _loadedModelId = null
    }
}
