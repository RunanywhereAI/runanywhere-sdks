package com.runanywhere.sdk.models.enums

import kotlinx.serialization.Serializable

/**
 * Defines the input/output modalities a framework supports
 * Exact match with iOS FrameworkModality enum
 */
@Serializable
enum class FrameworkModality(
    val value: String,
    val displayName: String,
    val iconName: String,
) {
    TEXT_TO_TEXT("text-to-text", "Text Generation", "text_bubble"),
    VOICE_TO_TEXT("voice-to-text", "Speech Recognition", "mic"),
    TEXT_TO_VOICE("text-to-voice", "Text-to-Speech", "speaker_wave_2"),
    IMAGE_TO_TEXT("image-to-text", "Image Understanding", "photo_badge_arrow_down"),
    TEXT_TO_IMAGE("text-to-image", "Image Generation", "photo_badge_plus"),
    MULTIMODAL("multimodal", "Multimodal", "sparkles"),
    ;

    companion object {
        fun fromValue(value: String): FrameworkModality? = entries.find { it.value == value }
    }
}

/**
 * Extension property to get primary modality for a framework
 * Matches iOS InferenceFramework.primaryModality
 */
val InferenceFramework.primaryModality: FrameworkModality
    get() =
        when (this) {
            // Voice frameworks
            InferenceFramework.WHISPER_KIT, InferenceFramework.WHISPER_CPP, InferenceFramework.OPEN_AI_WHISPER -> FrameworkModality.VOICE_TO_TEXT

            // Text generation frameworks
            InferenceFramework.LLAMA_CPP, InferenceFramework.MLX, InferenceFramework.MLC,
            InferenceFramework.EXECU_TORCH, InferenceFramework.PICO_LLM,
            -> FrameworkModality.TEXT_TO_TEXT

            // Text-focused frameworks
            InferenceFramework.SWIFT_TRANSFORMERS, InferenceFramework.FOUNDATION_MODELS -> FrameworkModality.TEXT_TO_TEXT

            // General ML frameworks that can support multiple modalities
            InferenceFramework.CORE_ML, InferenceFramework.TENSOR_FLOW_LITE, InferenceFramework.ONNX, InferenceFramework.MEDIA_PIPE -> FrameworkModality.MULTIMODAL

            // System TTS
            InferenceFramework.SYSTEM_TTS -> FrameworkModality.TEXT_TO_VOICE

            // FluidAudio - speaker diarization
            InferenceFramework.FLUID_AUDIO -> FrameworkModality.VOICE_TO_TEXT

            // Built-in (e.g., energy-based VAD) - voice processing
            InferenceFramework.BUILT_IN -> FrameworkModality.VOICE_TO_TEXT

            // Unknown/None - default to multimodal
            InferenceFramework.NONE, InferenceFramework.UNKNOWN -> FrameworkModality.MULTIMODAL
        }

/**
 * Extension property to get all supported modalities for a framework
 * Matches iOS InferenceFramework.supportedModalities
 */
val InferenceFramework.supportedModalities: Set<FrameworkModality>
    get() =
        when (this) {
            // Voice-only frameworks
            InferenceFramework.WHISPER_KIT, InferenceFramework.WHISPER_CPP, InferenceFramework.OPEN_AI_WHISPER ->
                setOf(
                    FrameworkModality.VOICE_TO_TEXT,
                )

            // Text-only frameworks
            InferenceFramework.LLAMA_CPP, InferenceFramework.MLX, InferenceFramework.MLC,
            InferenceFramework.EXECU_TORCH, InferenceFramework.PICO_LLM,
            -> setOf(FrameworkModality.TEXT_TO_TEXT)

            // Foundation Models might support multimodal in future
            InferenceFramework.FOUNDATION_MODELS -> setOf(FrameworkModality.TEXT_TO_TEXT)

            // Swift Transformers could support various modalities
            InferenceFramework.SWIFT_TRANSFORMERS -> setOf(FrameworkModality.TEXT_TO_TEXT, FrameworkModality.IMAGE_TO_TEXT)

            // General frameworks can support multiple modalities
            InferenceFramework.CORE_ML ->
                setOf(
                    FrameworkModality.TEXT_TO_TEXT,
                    FrameworkModality.VOICE_TO_TEXT,
                    FrameworkModality.TEXT_TO_VOICE,
                    FrameworkModality.IMAGE_TO_TEXT,
                    FrameworkModality.TEXT_TO_IMAGE,
                )

            InferenceFramework.TENSOR_FLOW_LITE ->
                setOf(
                    FrameworkModality.TEXT_TO_TEXT,
                    FrameworkModality.VOICE_TO_TEXT,
                    FrameworkModality.IMAGE_TO_TEXT,
                )

            // ONNX supports STT (Sherpa Whisper) and TTS (Piper) models
            InferenceFramework.ONNX ->
                setOf(
                    FrameworkModality.TEXT_TO_TEXT,
                    FrameworkModality.VOICE_TO_TEXT,
                    FrameworkModality.TEXT_TO_VOICE, // Piper TTS models
                    FrameworkModality.IMAGE_TO_TEXT,
                )

            InferenceFramework.MEDIA_PIPE ->
                setOf(
                    FrameworkModality.TEXT_TO_TEXT,
                    FrameworkModality.VOICE_TO_TEXT,
                    FrameworkModality.IMAGE_TO_TEXT,
                )

            // System TTS - text-to-voice only
            InferenceFramework.SYSTEM_TTS -> setOf(FrameworkModality.TEXT_TO_VOICE)

            // FluidAudio - speaker diarization
            InferenceFramework.FLUID_AUDIO -> setOf(FrameworkModality.VOICE_TO_TEXT)

            // Built-in (e.g., energy-based VAD) - voice activity detection
            InferenceFramework.BUILT_IN -> setOf(FrameworkModality.VOICE_TO_TEXT)

            // Unknown/None - empty set
            InferenceFramework.NONE, InferenceFramework.UNKNOWN -> emptySet()
        }

/**
 * Whether this framework is primarily for voice/audio processing
 */
val InferenceFramework.isVoiceFramework: Boolean
    get() = primaryModality == FrameworkModality.VOICE_TO_TEXT || primaryModality == FrameworkModality.TEXT_TO_VOICE

/**
 * Whether this framework is primarily for text generation
 */
val InferenceFramework.isTextGenerationFramework: Boolean
    get() = primaryModality == FrameworkModality.TEXT_TO_TEXT

/**
 * Whether this framework supports image processing
 */
val InferenceFramework.supportsImageProcessing: Boolean
    get() =
        supportedModalities.contains(FrameworkModality.IMAGE_TO_TEXT) ||
            supportedModalities.contains(FrameworkModality.TEXT_TO_IMAGE)
