package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.stt.STTService
import com.runanywhere.sdk.features.tts.TTSOptions
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADService
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.STTServiceProvider
import com.runanywhere.sdk.core.TTSServiceProvider
import com.runanywhere.sdk.core.VADServiceProvider
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.coroutines.flow.Flow

/**
 * ONNX STT Service Provider
 * Creates Speech-to-Text services using ONNX Runtime backend
 *
 * Matches iOS ONNXSTTServiceProvider
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXServiceProvider.swift
 */
class ONNXSTTServiceProvider : STTServiceProvider {
    private val logger = SDKLogger("ONNXSTTServiceProvider")

    override val name: String = "ONNX Runtime"
    override val framework: InferenceFramework = InferenceFramework.ONNX

    /**
     * Version of ONNX Runtime used
     */
    val version: String = "1.23.2"

    /**
     * Check if this provider can handle a model
     * Matches iOS canHandle(modelId:) pattern matching
     */
    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false

        val lowercased = modelId.lowercase()

        // Pattern matching for ONNX-compatible models
        return lowercased.contains("onnx") ||
                lowercased.contains("zipformer") ||
                lowercased.contains("sherpa") ||
                lowercased.contains("whisper") && (lowercased.contains("onnx") || lowercased.contains("sherpa")) ||
                lowercased.contains("distil") ||
                lowercased.contains("glados") ||
                lowercased.contains("paraformer")
    }

    /**
     * Create an STT service with the given configuration
     */
    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        logger.info("Creating ONNX STT service")
        return createONNXSTTService(configuration)
    }

    /**
     * Register this provider with ModuleRegistry
     */
    fun register(priority: Int = 100) {
        ModuleRegistry.shared.registerSTT(this)
        logger.info("ONNXSTTServiceProvider registered with priority $priority")
    }

    companion object {
        private val shared = ONNXSTTServiceProvider()

        /**
         * Register the ONNX STT provider
         */
        fun register(priority: Int = 100) {
            shared.register(priority)
        }
    }
}

/**
 * ONNX TTS Service Provider
 * Creates Text-to-Speech services using ONNX Runtime backend
 *
 * Matches iOS ONNXTTSServiceProvider
 */
class ONNXTTSServiceProvider : TTSServiceProvider {
    private val logger = SDKLogger("ONNXTTSServiceProvider")

    override val name: String = "ONNX TTS"
    override val framework: InferenceFramework = InferenceFramework.ONNX

    /**
     * Version of ONNX TTS implementation
     */
    val version: String = "1.0.0"

    /**
     * Check if this provider can handle a model
     * Matches iOS canHandle(modelId:) pattern matching
     */
    override fun canHandle(modelId: String): Boolean {
        val lowercased = modelId.lowercase()

        // Pattern matching for ONNX TTS models
        return lowercased.contains("piper") ||
                lowercased.contains("vits") ||
                lowercased.contains("sherpa-onnx") && lowercased.contains("tts") ||
                (lowercased.contains("tts") && lowercased.contains("onnx"))
    }

    /**
     * Synthesize text to speech
     */
    override suspend fun synthesize(text: String, options: TTSOptions): ByteArray {
        logger.info("Synthesizing with ONNX TTS: ${text.take(50)}...")
        return synthesizeWithONNX(text, options)
    }

    /**
     * Stream synthesized audio
     */
    override fun synthesizeStream(text: String, options: TTSOptions): Flow<ByteArray> {
        logger.info("Streaming synthesis with ONNX TTS: ${text.take(50)}...")
        return synthesizeStreamWithONNX(text, options)
    }

    /**
     * Register this provider with ModuleRegistry
     */
    fun register(priority: Int = 100) {
        ModuleRegistry.shared.registerTTS(this)
        logger.info("ONNXTTSServiceProvider registered with priority $priority")
    }

    companion object {
        private val shared = ONNXTTSServiceProvider()

        /**
         * Register the ONNX TTS provider
         */
        fun register(priority: Int = 100) {
            shared.register(priority)
        }
    }
}

/**
 * ONNX VAD Service Provider
 * Creates Voice Activity Detection services using ONNX Runtime backend
 */
class ONNXVADServiceProvider : VADServiceProvider {
    private val logger = SDKLogger("ONNXVADServiceProvider")

    override val name: String = "ONNX VAD"

    /**
     * Check if this provider can handle a model
     */
    override fun canHandle(modelId: String): Boolean {
        val lowercased = modelId.lowercase()
        return lowercased.contains("silero") ||
                lowercased.contains("vad") && lowercased.contains("onnx")
    }

    /**
     * Create a VAD service with the given configuration
     */
    override suspend fun createVADService(configuration: VADConfiguration): VADService {
        logger.info("Creating ONNX VAD service")
        return createONNXVADService(configuration)
    }

    /**
     * Register this provider with ModuleRegistry
     */
    fun register(priority: Int = 100) {
        ModuleRegistry.shared.registerVAD(this)
        logger.info("ONNXVADServiceProvider registered with priority $priority")
    }

    companion object {
        private val shared = ONNXVADServiceProvider()

        /**
         * Register the ONNX VAD provider
         */
        fun register(priority: Int = 100) {
            shared.register(priority)
        }
    }
}

// Platform-specific service creation functions (expect declarations)
// These are implemented in jvmAndroidMain

/**
 * Create an ONNX STT service (platform-specific implementation)
 */
expect suspend fun createONNXSTTService(configuration: STTConfiguration): STTService

/**
 * Synthesize text using ONNX TTS (platform-specific implementation)
 */
expect suspend fun synthesizeWithONNX(text: String, options: TTSOptions): ByteArray

/**
 * Stream synthesize text using ONNX TTS (platform-specific implementation)
 */
expect fun synthesizeStreamWithONNX(text: String, options: TTSOptions): Flow<ByteArray>

/**
 * Create an ONNX VAD service (platform-specific implementation)
 */
expect suspend fun createONNXVADService(configuration: VADConfiguration): VADService
