package com.runanywhere.runanywhereai.domain.models

/**
 * Events emitted by the voice pipeline
 * TODO: These will be provided by the SDK's enhanced voice pipeline
 */
sealed class VoicePipelineEvent {
    object VADSpeechStart : VoicePipelineEvent()
    object VADSpeechEnd : VoicePipelineEvent()

    data class STTPartialTranscript(
        val text: String,
        val confidence: Float
    ) : VoicePipelineEvent()

    data class STTFinalTranscript(
        val text: String,
        val confidence: Float,
        val speaker: SpeakerInfo? = null
    ) : VoicePipelineEvent()

    data class LLMResponse(
        val text: String,
        val thinking: String? = null
    ) : VoicePipelineEvent()

    data class TTSStart(val text: String) : VoicePipelineEvent()
    object TTSComplete : VoicePipelineEvent()

    data class Error(val message: String) : VoicePipelineEvent()
}

/**
 * Configuration for the modular pipeline
 * TODO: This will be used to configure the SDK's pipeline components
 */
data class ModularPipelineConfig(
    val components: List<PipelineComponent>,
    val vadConfig: VADConfig = VADConfig(),
    val sttConfig: VoiceSTTConfig,
    val llmConfig: VoiceLLMConfig = VoiceLLMConfig(),
    val ttsConfig: VoiceTTSConfig = VoiceTTSConfig(),
    val enableSpeakerDiarization: Boolean = false,
    val speakerConfig: SpeakerDiarizationConfig = SpeakerDiarizationConfig()
)

enum class PipelineComponent {
    VAD, STT, LLM, TTS
}

/**
 * Session states for voice interaction
 */
enum class SessionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    LISTENING,
    PROCESSING,
    SPEAKING,
    ERROR
}

// TODO: These configuration classes will be provided by the SDK
data class VADConfig(
    val sensitivity: Float = 0.5f,
    val minSpeechDuration: Long = 250,
    val minSilenceDuration: Long = 500
)

data class VoiceSTTConfig(
    val modelId: String,
    val language: String = "auto",
    val enableRealTime: Boolean = true
)

data class VoiceLLMConfig(
    val modelId: String = "default",
    val maxTokens: Int = 150,
    val temperature: Float = 0.7f
)

data class VoiceTTSConfig(
    val voice: String = "default"
)

data class SpeakerDiarizationConfig(
    val threshold: Float = 0.45f,
    val maxSpeakers: Int = 8
)
