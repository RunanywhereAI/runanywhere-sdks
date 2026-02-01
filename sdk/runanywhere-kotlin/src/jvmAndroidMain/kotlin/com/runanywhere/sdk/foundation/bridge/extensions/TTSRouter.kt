/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * TTS Router - Routes TTS operations to the appropriate backend.
 * 
 * Backends:
 * - KokoroTTSProvider: For Kokoro models (NPU-accelerated via QNN on Qualcomm devices)
 * - CppBridgeTTS: For other models (Sherpa-ONNX on CPU)
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKError
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Routes TTS operations to the appropriate backend based on model type.
 * 
 * For Kokoro models: Uses KokoroTTSProvider (ONNX Runtime + QNN EP on Android)
 * For other models: Uses CppBridgeTTS (Sherpa-ONNX via C++)
 */
object TTSRouter {
    private const val TAG = "TTSRouter"
    private val logger = SDKLogger(TAG)
    
    /**
     * Backend type currently in use.
     */
    sealed class Backend {
        data object SherpaOnnx : Backend() {
            override fun toString() = "SherpaOnnx (CppBridgeTTS)"
        }
        data object KokoroQnn : Backend() {
            override fun toString() = "KokoroQnn (NPU)"
        }
    }
    
    @Volatile
    private var _currentBackend: Backend? = null
    
    @Volatile
    private var _loadedModelId: String? = null
    
    @Volatile
    private var _loadedModelName: String? = null
    
    private val lock = Any()
    private val loadMutex = Mutex()
    
    /**
     * Current backend in use.
     */
    val currentBackend: Backend?
        get() = _currentBackend
    
    /**
     * Human-readable backend name for logging.
     */
    val backendName: String
        get() = _currentBackend?.toString() ?: "None"
    
    /**
     * Check if a model is loaded.
     */
    val isLoaded: Boolean
        get() = synchronized(lock) {
            when (_currentBackend) {
                is Backend.KokoroQnn -> KokoroTTSRegistry.provider?.isLoaded == true
                is Backend.SherpaOnnx -> CppBridgeTTS.isLoaded
                null -> false
            }
        }
    
    /**
     * Get the loaded model ID.
     */
    fun getLoadedModelId(): String? = synchronized(lock) {
        when (_currentBackend) {
            is Backend.KokoroQnn -> KokoroTTSRegistry.provider?.loadedModelId
            is Backend.SherpaOnnx -> CppBridgeTTS.getLoadedModelId()
            null -> null
        }
    }
    
    /**
     * Load a TTS model.
     * 
     * Routes to Kokoro if the model ID/name contains "kokoro" and
     * a KokoroTTSProvider is registered. Otherwise uses CppBridgeTTS.
     * 
     * @param modelPath Path to the model directory/file
     * @param modelId Model identifier
     * @param modelName Human-readable model name
     * @return Result indicating success or failure
     */
    suspend fun loadModel(
        modelPath: String,
        modelId: String,
        modelName: String?
    ): Result<Unit> = loadMutex.withLock {
        logger.info("Loading TTS model: $modelId from $modelPath")
        logger.info("KokoroTTSRegistry.hasProvider = ${KokoroTTSRegistry.hasProvider}")
        logger.info("KokoroTTSRegistry.provider = ${KokoroTTSRegistry.provider}")
        
        // Unload any existing model first (without lock since we already hold it)
        unloadInternal()
        
        // Determine which backend to use
        val useKokoro = KokoroTTSRegistry.shouldUseKokoro(modelId, modelName)
        logger.info("shouldUseKokoro($modelId, $modelName) = $useKokoro")
        
        if (useKokoro) {
            logger.info("Using Kokoro backend for model: $modelId")
            loadWithKokoro(modelPath, modelId, modelName)
        } else {
            logger.info("Using SherpaOnnx backend for model: $modelId")
            loadWithSherpaOnnx(modelPath, modelId, modelName)
        }
    }
    
    private suspend fun loadWithKokoro(
        modelPath: String,
        modelId: String,
        modelName: String?
    ): Result<Unit> {
        val provider = KokoroTTSRegistry.provider
            ?: return Result.failure(SDKError.tts("Kokoro provider not registered"))
        
        logger.info("Loading Kokoro model: $modelId (NPU-accelerated)")
        
        return provider.loadModel(modelPath, modelId).onSuccess {
            _currentBackend = Backend.KokoroQnn
            _loadedModelId = modelId
            _loadedModelName = modelName
            logger.info("Kokoro model loaded successfully: $modelId")
        }.onFailure { error ->
            logger.error("Failed to load Kokoro model: ${error.message}")
        }
    }
    
    private fun loadWithSherpaOnnx(
        modelPath: String,
        modelId: String,
        modelName: String?
    ): Result<Unit> {
        logger.info("Loading TTS model with SherpaOnnx: $modelId")
        
        val result = CppBridgeTTS.loadModel(modelPath, modelId, modelName)
        
        return if (result == 0) {
            _currentBackend = Backend.SherpaOnnx
            _loadedModelId = modelId
            _loadedModelName = modelName
            logger.info("SherpaOnnx model loaded successfully: $modelId")
            Result.success(Unit)
        } else {
            val errorMsg = "Failed to load TTS model (error: $result)"
            logger.error(errorMsg)
            Result.failure(SDKError.tts(errorMsg))
        }
    }
    
    /**
     * Synthesize speech from text.
     * 
     * @param text Text to synthesize
     * @param config Synthesis configuration
     * @return Synthesis result with WAV audio data
     */
    suspend fun synthesize(
        text: String,
        config: CppBridgeTTS.SynthesisConfig
    ): Result<CppBridgeTTS.SynthesisResult> {
        return when (_currentBackend) {
            is Backend.KokoroQnn -> synthesizeWithKokoro(text, config)
            is Backend.SherpaOnnx -> synthesizeWithSherpaOnnx(text, config)
            null -> Result.failure(SDKError.tts("No TTS model loaded"))
        }
    }
    
    private suspend fun synthesizeWithKokoro(
        text: String,
        config: CppBridgeTTS.SynthesisConfig
    ): Result<CppBridgeTTS.SynthesisResult> {
        val provider = KokoroTTSRegistry.provider
            ?: return Result.failure(SDKError.tts("Kokoro provider not available"))
        
        logger.debug("Synthesizing with Kokoro: \"${text.take(50)}...\"")
        
        // Extract voice from config or use default
        val voice = config.voiceId.ifEmpty { "af_bella" }
        val speed = config.speed
        
        return provider.synthesize(text, voice, speed).map { kokoroResult ->
            // Convert Kokoro result to CppBridgeTTS.SynthesisResult
            val startTime = System.currentTimeMillis()
            
            // Convert Float32 PCM to WAV
            val wavData = convertFloat32ToWav(kokoroResult.samples, kokoroResult.sampleRate)
            
            val conversionTime = System.currentTimeMillis() - startTime
            logger.debug("Audio conversion: ${kokoroResult.samples.size} samples → ${wavData.size} bytes WAV in ${conversionTime}ms")
            
            CppBridgeTTS.SynthesisResult(
                audioData = wavData,
                text = text,
                durationMs = (kokoroResult.durationSeconds * 1000).toLong(),
                completionReason = CppBridgeTTS.CompletionReason.END_OF_TEXT,
                sampleRate = kokoroResult.sampleRate,
                audioFormat = CppBridgeTTS.AudioFormat.WAV,
                processingTimeMs = kokoroResult.inferenceTimeMs + conversionTime
            )
        }
    }
    
    private fun synthesizeWithSherpaOnnx(
        text: String,
        config: CppBridgeTTS.SynthesisConfig
    ): Result<CppBridgeTTS.SynthesisResult> {
        logger.debug("Synthesizing with SherpaOnnx: \"${text.take(50)}...\"")
        
        return try {
            val result = CppBridgeTTS.synthesize(text, config)
            Result.success(result)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    /**
     * Synthesize with streaming output.
     */
    suspend fun synthesizeStream(
        text: String,
        config: CppBridgeTTS.SynthesisConfig,
        callback: CppBridgeTTS.StreamCallback
    ): Result<CppBridgeTTS.SynthesisResult> {
        // For now, Kokoro doesn't support streaming, fall back to regular synthesis
        return when (_currentBackend) {
            is Backend.KokoroQnn -> {
                // Synthesize full audio, then call callback with entire result
                synthesizeWithKokoro(text, config).map { result ->
                    callback.onAudioChunk(result.audioData, true)
                    result
                }
            }
            is Backend.SherpaOnnx -> {
                try {
                    val result = CppBridgeTTS.synthesizeStream(text, config, callback)
                    Result.success(result)
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
            null -> Result.failure(SDKError.tts("No TTS model loaded"))
        }
    }
    
    /**
     * Get available voices for the current model.
     */
    fun getAvailableVoices(): List<CppBridgeTTS.VoiceInfo> {
        return when (_currentBackend) {
            is Backend.KokoroQnn -> {
                // Convert Kokoro voices to VoiceInfo
                KokoroTTSRegistry.provider?.listVoices()?.map { voiceId ->
                    CppBridgeTTS.VoiceInfo(
                        voiceId = voiceId,
                        name = voiceId,
                        language = "en", // Kokoro default
                        gender = if (voiceId.startsWith("af_")) "female" else "male",
                        quality = "neural"
                    )
                } ?: emptyList()
            }
            is Backend.SherpaOnnx -> CppBridgeTTS.getAvailableVoices()
            null -> emptyList()
        }
    }
    
    /**
     * Cancel ongoing synthesis.
     */
    fun cancel() {
        when (_currentBackend) {
            is Backend.KokoroQnn -> {
                // Kokoro doesn't have explicit cancel - synthesis is synchronous
                logger.debug("Cancel requested (Kokoro synthesis is synchronous)")
            }
            is Backend.SherpaOnnx -> CppBridgeTTS.cancel()
            null -> { /* No-op */ }
        }
    }
    
    /**
     * Unload the current model.
     */
    fun unload() {
        synchronized(lock) {
            unloadInternal()
        }
    }
    
    /**
     * Internal unload without lock (for use when lock is already held).
     */
    private fun unloadInternal() {
        when (_currentBackend) {
            is Backend.KokoroQnn -> {
                KokoroTTSRegistry.provider?.unload()
                logger.info("Kokoro model unloaded")
            }
            is Backend.SherpaOnnx -> {
                CppBridgeTTS.unload()
                logger.info("SherpaOnnx model unloaded")
            }
            null -> { /* Already unloaded */ }
        }
        
        _currentBackend = null
        _loadedModelId = null
        _loadedModelName = null
    }
    
    // ========================================================================
    // AUDIO CONVERSION
    // ========================================================================
    
    /**
     * Convert Float32 PCM samples to WAV format.
     * 
     * Kokoro outputs Float32 PCM samples in range [-1.0, 1.0].
     * This function converts to 16-bit signed PCM WAV format
     * which is compatible with Android's AudioTrack and media players.
     * 
     * @param samples Float32 PCM samples
     * @param sampleRate Sample rate in Hz
     * @return WAV file as ByteArray
     */
    private fun convertFloat32ToWav(samples: FloatArray, sampleRate: Int): ByteArray {
        // Convert Float32 [-1.0, 1.0] to Int16 [-32768, 32767]
        val int16Samples = ShortArray(samples.size) { i ->
            val clamped = samples[i].coerceIn(-1.0f, 1.0f)
            (clamped * 32767).toInt().toShort()
        }
        
        // WAV file structure:
        // - 44 byte header
        // - PCM data (2 bytes per sample for 16-bit)
        val pcmDataSize = int16Samples.size * 2
        val totalSize = 44 + pcmDataSize
        
        val buffer = ByteBuffer.allocate(totalSize).order(ByteOrder.LITTLE_ENDIAN)
        
        // RIFF header
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(totalSize - 8)  // File size minus RIFF header
        buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
        
        // fmt subchunk
        buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)              // Subchunk1 size (16 for PCM)
        buffer.putShort(1)             // Audio format (1 = PCM)
        buffer.putShort(1)             // Number of channels (1 = mono)
        buffer.putInt(sampleRate)      // Sample rate
        buffer.putInt(sampleRate * 2)  // Byte rate (sampleRate * numChannels * bitsPerSample/8)
        buffer.putShort(2)             // Block align (numChannels * bitsPerSample/8)
        buffer.putShort(16)            // Bits per sample
        
        // data subchunk
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(pcmDataSize)     // Subchunk2 size
        
        // Write PCM samples
        for (sample in int16Samples) {
            buffer.putShort(sample)
        }
        
        return buffer.array()
    }
}
