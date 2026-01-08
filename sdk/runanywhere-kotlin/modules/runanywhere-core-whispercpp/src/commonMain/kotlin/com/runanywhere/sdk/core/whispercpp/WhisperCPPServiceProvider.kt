package com.runanywhere.sdk.core.whispercpp

import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.STTServiceProvider
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.LLMFramework

/**
 * WhisperCPP STT Service Provider
 * Creates Speech-to-Text services using whisper.cpp backend
 *
 * Matches iOS WhisperCPPSTTServiceProvider
 * Reference: sdk/runanywhere-swift/Sources/WhisperCPPRuntime/WhisperCPPServiceProvider.swift
 */
class WhisperCPPSTTServiceProvider : STTServiceProvider {
    private val logger = SDKLogger("WhisperCPPSTTServiceProvider")

    override val name: String = "WhisperCPP"
    override val framework: LLMFramework = LLMFramework.WHISPER_CPP

    /**
     * Version of whisper.cpp library
     */
    val version: String = "1.7.2"

    /**
     * Check if this provider can handle a model
     * Matches iOS canHandle(modelId:) pattern matching
     */
    override fun canHandle(modelId: String?): Boolean {
        if (modelId == null) return false

        val lowercased = modelId.lowercase()

        // Handle GGML whisper models (primary format for whisper.cpp)
        if (lowercased.contains("ggml") && lowercased.contains("whisper")) {
            return true
        }

        // Handle .bin whisper models (GGML format)
        if (lowercased.contains("whisper") && lowercased.endsWith(".bin")) {
            return true
        }

        // Handle explicit whispercpp references
        if (lowercased.contains("whispercpp") ||
            lowercased.contains("whisper-cpp") ||
            lowercased.contains("whisper_cpp")) {
            return true
        }

        // Handle whisper model size patterns (tiny, base, small, medium, large)
        // These often indicate GGML models: whisper-tiny, whisper-base-q5_1, etc.
        val whisperSizePattern = Regex("whisper[_-]?(tiny|base|small|medium|large|turbo)", RegexOption.IGNORE_CASE)
        if (whisperSizePattern.containsMatchIn(lowercased)) {
            // Only match if it looks like a GGML model (not ONNX or sherpa)
            if (!lowercased.contains("onnx") && !lowercased.contains("sherpa")) {
                return true
            }
        }

        return false
    }

    /**
     * Create an STT service with the given configuration
     */
    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        logger.info("Creating WhisperCPP STT service")
        return createWhisperCPPSTTService(configuration)
    }

    /**
     * Register this provider with ModuleRegistry
     */
    fun register(priority: Int = 90) {
        ModuleRegistry.shared.registerSTT(this)
        logger.info("WhisperCPPSTTServiceProvider registered with priority $priority")
    }

    companion object {
        private val shared = WhisperCPPSTTServiceProvider()

        /**
         * Register the WhisperCPP STT provider
         */
        fun register(priority: Int = 90) {
            shared.register(priority)
        }
    }
}

// Platform-specific service creation function (expect declaration)
// Implemented in jvmAndroidMain

/**
 * Create a WhisperCPP STT service (platform-specific implementation)
 */
expect suspend fun createWhisperCPPSTTService(configuration: STTConfiguration): STTService
