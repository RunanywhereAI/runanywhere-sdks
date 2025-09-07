package com.runanywhere.sdk.components.stt

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.STTServiceProvider
import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Whisper STT Service Provider
 */
class WhisperServiceProvider : STTServiceProvider {
    private val logger = SDKLogger("WhisperServiceProvider")

    override val name: String = "WhisperSTT"

    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        logger.info("Creating Whisper STT Service")
        return WhisperSTTService()
    }

    override fun canHandle(modelId: String?): Boolean {
        // Can handle whisper models or default requests
        return modelId == null || modelId.contains("whisper", ignoreCase = true)
    }

    companion object {
        /**
         * Register this provider with the module registry
         */
        fun register() {
            ModuleRegistry.registerSTT(WhisperServiceProvider())
        }
    }
}
