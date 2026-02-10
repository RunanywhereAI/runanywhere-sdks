/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * TTS Router - Routes TTS operations to the appropriate backend.
 *
 * Backend:
 * - CppBridgeTTS: Sherpa-ONNX on CPU
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKError
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Routes TTS operations to CppBridgeTTS (Sherpa-ONNX).
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
    }

    @Volatile
    private var _currentBackend: Backend? = null

    @Volatile
    private var _loadedModelId: String? = null

    @Volatile
    private var _loadedModelName: String? = null

    private val lock = Any()
    private val loadMutex = Mutex()

    val currentBackend: Backend?
        get() = _currentBackend

    val backendName: String
        get() = _currentBackend?.toString() ?: "None"

    val isLoaded: Boolean
        get() = synchronized(lock) {
            when (_currentBackend) {
                is Backend.SherpaOnnx -> CppBridgeTTS.isLoaded
                null -> false
            }
        }

    fun getLoadedModelId(): String? = synchronized(lock) {
        when (_currentBackend) {
            is Backend.SherpaOnnx -> CppBridgeTTS.getLoadedModelId()
            null -> null
        }
    }

    /**
     * Load a TTS model via CppBridgeTTS (Sherpa-ONNX).
     */
    suspend fun loadModel(
        modelPath: String,
        modelId: String,
        modelName: String?
    ): Result<Unit> = loadMutex.withLock {
        logger.info("Loading TTS model: $modelId from $modelPath")

        unloadInternal()

        logger.info("Using SherpaOnnx backend for model: $modelId")
        val result = loadWithSherpaOnnx(modelPath, modelId, modelName)
        if (result == 0) {
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

    private fun loadWithSherpaOnnx(
        modelPath: String,
        modelId: String,
        modelName: String?
    ): Int {
        logger.info("Loading TTS model with SherpaOnnx: $modelId")
        return CppBridgeTTS.loadModel(modelPath, modelId, modelName)
    }

    suspend fun synthesize(
        text: String,
        config: CppBridgeTTS.SynthesisConfig
    ): Result<CppBridgeTTS.SynthesisResult> {
        return when (_currentBackend) {
            is Backend.SherpaOnnx -> synthesizeWithSherpaOnnx(text, config)
            null -> Result.failure(SDKError.tts("No TTS model loaded"))
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

    suspend fun synthesizeStream(
        text: String,
        config: CppBridgeTTS.SynthesisConfig,
        callback: CppBridgeTTS.StreamCallback
    ): Result<CppBridgeTTS.SynthesisResult> {
        return when (_currentBackend) {
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

    fun getAvailableVoices(): List<CppBridgeTTS.VoiceInfo> {
        return when (_currentBackend) {
            is Backend.SherpaOnnx -> CppBridgeTTS.getAvailableVoices()
            null -> emptyList()
        }
    }

    fun cancel() {
        when (_currentBackend) {
            is Backend.SherpaOnnx -> CppBridgeTTS.cancel()
            null -> { /* No-op */ }
        }
    }

    fun unload() {
        synchronized(lock) {
            unloadInternal()
        }
    }

    private fun unloadInternal() {
        when (_currentBackend) {
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
}
