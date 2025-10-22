package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.llm.LLMConfiguration
import com.runanywhere.sdk.components.TTSConfiguration
import com.runanywhere.sdk.components.TTSVoice
import com.runanywhere.sdk.components.TTSGender
import com.runanywhere.sdk.voice.ModularVoicePipeline

// MARK: - Pipeline Component Enum (for simplified API)

/**
 * Simplified pipeline component enum for app-level configuration
 * Maps to SDKComponent but provides a simpler interface
 * Matches iOS PipelineComponent (though iOS uses SDKComponent directly)
 */
enum class PipelineComponent {
    VAD, STT, LLM, TTS;

    fun toSDKComponent(): SDKComponent = when (this) {
        VAD -> SDKComponent.VAD
        STT -> SDKComponent.STT
        LLM -> SDKComponent.LLM
        TTS -> SDKComponent.TTS
    }

    companion object {
        fun fromSDKComponent(component: SDKComponent): PipelineComponent? = when (component) {
            SDKComponent.VAD -> VAD
            SDKComponent.STT -> STT
            SDKComponent.LLM -> LLM
            SDKComponent.TTS -> TTS
            else -> null
        }
    }
}

// MARK: - Modular Pipeline Configuration

/**
 * Configuration for the modular voice pipeline
 * Matches iOS ModularPipelineConfig
 */
data class ModularPipelineConfig(
    val components: List<SDKComponent>,
    val vadConfig: VADConfiguration? = null,
    val sttConfig: STTConfiguration? = null,
    val llmConfig: LLMConfiguration? = null,
    val ttsConfig: TTSConfiguration? = null
) {
    companion object {
        /**
         * Convenience initializer with simplified parameters
         * Matches iOS convenience init
         */
        fun create(
            components: List<PipelineComponent>,
            vad: VADConfig? = null,
            stt: VoiceSTTConfig? = null,
            llm: VoiceLLMConfig? = null,
            tts: VoiceTTSConfig? = null
        ): ModularPipelineConfig {
            return ModularPipelineConfig(
                components = components.map { it.toSDKComponent() },
                vadConfig = vad?.let { VADConfiguration(energyThreshold = it.energyThreshold) },
                sttConfig = stt?.let {
                    STTConfiguration(
                        modelId = it.modelId,
                        language = it.language
                    )
                },
                llmConfig = llm?.let {
                    LLMConfiguration(
                        modelId = it.modelId,
                        temperature = 0.3,  // Double type
                        maxTokens = it.maxTokens ?: 100,
                        systemPrompt = it.systemPrompt,
                        streamingEnabled = true
                    )
                },
                ttsConfig = tts?.let {
                    TTSConfiguration(
                        defaultVoice = TTSVoice(
                            id = it.voice,
                            name = it.voice,
                            language = "en-US",
                            gender = TTSGender.NEUTRAL
                        )
                    )
                }
            )
        }

        /**
         * Create a configuration for transcription with VAD
         */
        fun transcriptionWithVAD(
            sttModel: String = "whisper-base",
            vadThreshold: Float = 0.01f
        ): ModularPipelineConfig {
            return create(
                components = listOf(PipelineComponent.VAD, PipelineComponent.STT),
                vad = VADConfig(energyThreshold = vadThreshold),
                stt = VoiceSTTConfig(modelId = sttModel, language = "en")
            )
        }
    }
}

// MARK: - Simplified Configuration Types for Sample App Compatibility

/**
 * Simplified VAD configuration
 * Matches iOS VADConfig
 */
data class VADConfig(
    val energyThreshold: Float = 0.01f
)

/**
 * Simplified STT configuration for voice
 * Matches iOS VoiceSTTConfig
 */
data class VoiceSTTConfig(
    val modelId: String = "whisper-base",
    val language: String = "en"
)

/**
 * Simplified LLM configuration for voice
 * Matches iOS VoiceLLMConfig
 */
data class VoiceLLMConfig(
    val modelId: String,
    val systemPrompt: String? = null,
    val maxTokens: Int? = null  // Optional - let model decide if not specified
)

/**
 * Simplified TTS configuration for voice
 * Matches iOS VoiceTTSConfig
 */
data class VoiceTTSConfig(
    val voice: String = "system"
)

// MARK: - Pipeline Extensions

/**
 * Create a modular voice pipeline
 * Matches iOS createVoicePipeline extension
 */
suspend fun RunAnywhere.createVoicePipeline(config: ModularPipelineConfig): ModularVoicePipeline {
    return ModularVoicePipeline(config)
}
