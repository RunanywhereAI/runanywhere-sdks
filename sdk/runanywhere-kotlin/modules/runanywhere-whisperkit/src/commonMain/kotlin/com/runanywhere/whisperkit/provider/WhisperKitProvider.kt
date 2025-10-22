package com.runanywhere.whisperkit.provider

import com.runanywhere.sdk.core.STTServiceProvider
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.whisperkit.service.WhisperKitFactory
import com.runanywhere.whisperkit.models.WhisperModelType

/**
 * WhisperKit adapter that bridges the generic STT interface with Whisper-specific implementation
 * This provider allows WhisperKit to be used as an STT service in the RunAnywhere SDK
 * Follows the same pattern as iOS WhisperKit module
 */
class WhisperKitProvider : STTServiceProvider {

    override val name: String = "WhisperKit"

    override val framework: LLMFramework = LLMFramework.WHISPER_KIT

    /**
     * Creates a WhisperKit service instance that implements the generic STTService interface
     * The returned service can be used with any STT-compatible component in the SDK
     */
    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        val whisperService = WhisperKitFactory.createService()

        // Map generic model ID to Whisper-specific model type
        configuration.modelId?.let { modelId ->
            val whisperModelType = mapGenericModelIdToWhisperType(modelId)
            whisperService.initializeWithWhisperModel(whisperModelType)
        } ?: run {
            // Use default Whisper model if no specific model requested
            whisperService.initializeWithWhisperModel(WhisperModelType.BASE)
        }

        // Return the service which implements the generic STTService interface
        return whisperService
    }

    /**
     * Checks if this provider can handle the requested model
     * WhisperKit handles all Whisper models and can serve as a default STT provider
     */
    override fun canHandle(modelId: String?): Boolean {
        // WhisperKit can handle:
        // 1. No specific model (use as default)
        // 2. Any model ID containing "whisper"
        // 3. Common size identifiers that map to Whisper models
        return modelId == null ||
               modelId.contains("whisper", ignoreCase = true) ||
               isWhisperCompatibleModelId(modelId)
    }

    /**
     * Maps generic model identifiers to Whisper-specific model types
     * This allows the SDK to use generic model names while WhisperKit uses its specific types
     */
    private fun mapGenericModelIdToWhisperType(modelId: String): WhisperModelType {
        return when (modelId.lowercase()) {
            // Whisper-specific IDs
            "whisper-tiny", "whisper.tiny" -> WhisperModelType.TINY
            "whisper-base", "whisper.base" -> WhisperModelType.BASE
            "whisper-small", "whisper.small" -> WhisperModelType.SMALL
            "whisper-medium", "whisper.medium" -> WhisperModelType.MEDIUM
            "whisper-large", "whisper.large" -> WhisperModelType.LARGE
            "whisper-large-v2", "whisper.large.v2" -> WhisperModelType.LARGE_V2
            "whisper-large-v3", "whisper.large.v3" -> WhisperModelType.LARGE_V3

            // Generic size identifiers
            "tiny", "smallest" -> WhisperModelType.TINY
            "base", "default" -> WhisperModelType.BASE
            "small" -> WhisperModelType.SMALL
            "medium" -> WhisperModelType.MEDIUM
            "large", "largest" -> WhisperModelType.LARGE_V3
            "large-v2" -> WhisperModelType.LARGE_V2
            "large-v3" -> WhisperModelType.LARGE_V3

            // Default fallback
            else -> WhisperModelType.BASE
        }
    }

    private fun isWhisperCompatibleModelId(modelId: String): Boolean {
        val compatibleIds = setOf(
            "tiny", "base", "small", "medium", "large",
            "smallest", "default", "largest",
            "large-v2", "large-v3"
        )
        return modelId.lowercase() in compatibleIds
    }

    companion object {
        /**
         * Register this provider with the module registry
         * This enables WhisperKit to be discovered and used as an STT service
         *
         * Usage:
         * ```
         * // In your application initialization
         * WhisperKitProvider.register()
         * ```
         */
        fun register() {
            // Register with the core SDK's module registry
            com.runanywhere.sdk.core.ModuleRegistry.registerSTT(WhisperKitProvider())
        }
    }
}
