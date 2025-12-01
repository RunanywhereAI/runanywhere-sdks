package com.runanywhere.sdk.models.enums

import kotlinx.serialization.Serializable

/**
 * Defines the input/output modalities a framework supports
 * Exact match with iOS FrameworkModality enum
 */
@Serializable
enum class FrameworkModality(val value: String, val displayName: String, val iconName: String) {
    TEXT_TO_TEXT("text-to-text", "Text Generation", "text_bubble"),
    VOICE_TO_TEXT("voice-to-text", "Speech Recognition", "mic"),
    TEXT_TO_VOICE("text-to-voice", "Text-to-Speech", "speaker_wave_2"),
    IMAGE_TO_TEXT("image-to-text", "Image Understanding", "photo_badge_arrow_down"),
    TEXT_TO_IMAGE("text-to-image", "Image Generation", "photo_badge_plus"),
    MULTIMODAL("multimodal", "Multimodal", "sparkles");

    companion object {
        fun fromValue(value: String): FrameworkModality? {
            return entries.find { it.value == value }
        }
    }
}

/**
 * Extension property to get primary modality for a framework
 * Matches iOS LLMFramework.primaryModality
 */
val LLMFramework.primaryModality: FrameworkModality
    get() = when (this) {
        // Voice frameworks
        LLMFramework.WHISPER_KIT, LLMFramework.WHISPER_CPP, LLMFramework.OPEN_AI_WHISPER -> FrameworkModality.VOICE_TO_TEXT

        // Text generation frameworks
        LLMFramework.LLAMA_CPP, LLMFramework.LLAMACPP, LLMFramework.MLX, LLMFramework.MLC,
        LLMFramework.EXECU_TORCH, LLMFramework.PICO_LLM -> FrameworkModality.TEXT_TO_TEXT

        // Text-focused frameworks
        LLMFramework.SWIFT_TRANSFORMERS, LLMFramework.FOUNDATION_MODELS -> FrameworkModality.TEXT_TO_TEXT

        // General ML frameworks that can support multiple modalities
        LLMFramework.CORE_ML, LLMFramework.TENSOR_FLOW_LITE, LLMFramework.ONNX, LLMFramework.MEDIA_PIPE -> FrameworkModality.MULTIMODAL

        // System TTS
        LLMFramework.SYSTEM_TTS -> FrameworkModality.TEXT_TO_VOICE
    }

/**
 * Extension property to get all supported modalities for a framework
 * Matches iOS LLMFramework.supportedModalities
 */
val LLMFramework.supportedModalities: Set<FrameworkModality>
    get() = when (this) {
        // Voice-only frameworks
        LLMFramework.WHISPER_KIT, LLMFramework.WHISPER_CPP, LLMFramework.OPEN_AI_WHISPER -> setOf(FrameworkModality.VOICE_TO_TEXT)

        // Text-only frameworks
        LLMFramework.LLAMA_CPP, LLMFramework.LLAMACPP, LLMFramework.MLX, LLMFramework.MLC,
        LLMFramework.EXECU_TORCH, LLMFramework.PICO_LLM -> setOf(FrameworkModality.TEXT_TO_TEXT)

        // Foundation Models might support multimodal in future
        LLMFramework.FOUNDATION_MODELS -> setOf(FrameworkModality.TEXT_TO_TEXT)

        // Swift Transformers could support various modalities
        LLMFramework.SWIFT_TRANSFORMERS -> setOf(FrameworkModality.TEXT_TO_TEXT, FrameworkModality.IMAGE_TO_TEXT)

        // General frameworks can support multiple modalities
        LLMFramework.CORE_ML -> setOf(
            FrameworkModality.TEXT_TO_TEXT,
            FrameworkModality.VOICE_TO_TEXT,
            FrameworkModality.TEXT_TO_VOICE,
            FrameworkModality.IMAGE_TO_TEXT,
            FrameworkModality.TEXT_TO_IMAGE
        )

        LLMFramework.TENSOR_FLOW_LITE, LLMFramework.ONNX -> setOf(
            FrameworkModality.TEXT_TO_TEXT,
            FrameworkModality.VOICE_TO_TEXT,
            FrameworkModality.IMAGE_TO_TEXT
        )

        LLMFramework.MEDIA_PIPE -> setOf(
            FrameworkModality.TEXT_TO_TEXT,
            FrameworkModality.VOICE_TO_TEXT,
            FrameworkModality.IMAGE_TO_TEXT
        )

        // System TTS - text-to-voice only
        LLMFramework.SYSTEM_TTS -> setOf(FrameworkModality.TEXT_TO_VOICE)
    }

/**
 * Whether this framework is primarily for voice/audio processing
 */
val LLMFramework.isVoiceFramework: Boolean
    get() = primaryModality == FrameworkModality.VOICE_TO_TEXT || primaryModality == FrameworkModality.TEXT_TO_VOICE

/**
 * Whether this framework is primarily for text generation
 */
val LLMFramework.isTextGenerationFramework: Boolean
    get() = primaryModality == FrameworkModality.TEXT_TO_TEXT

/**
 * Whether this framework supports image processing
 */
val LLMFramework.supportsImageProcessing: Boolean
    get() = supportedModalities.contains(FrameworkModality.IMAGE_TO_TEXT) ||
            supportedModalities.contains(FrameworkModality.TEXT_TO_IMAGE)
