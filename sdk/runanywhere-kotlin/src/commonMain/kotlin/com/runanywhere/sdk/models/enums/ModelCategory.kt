package com.runanywhere.sdk.models.enums

import kotlinx.serialization.Serializable

/**
 * Defines the category/type of a model based on its input/output modality
 * This aligns with FrameworkModality for consistency across the SDK
 */
@Serializable
enum class ModelCategory(
    val value: String,
    val displayName: String,
    val iconName: String
) {
    LANGUAGE("language", "Language Model", "text_bubble"),
    LANGUAGE_MODEL("language", "Language Model", "text_bubble"), // Alias for compatibility
    SPEECH_RECOGNITION("speech-recognition", "Speech Recognition", "mic"),
    SPEECH_SYNTHESIS("speech-synthesis", "Text-to-Speech", "speaker_wave_2"),
    VISION("vision", "Vision Model", "photo_badge_arrow_down"),
    IMAGE_GENERATION("image-generation", "Image Generation", "photo_badge_plus"),
    MULTIMODAL("multimodal", "Multimodal", "sparkles"),
    AUDIO("audio", "Audio Processing", "waveform");

    /**
     * Maps this category to its corresponding FrameworkModality
     * Matches iOS ModelCategory.frameworkModality property
     */
    val frameworkModality: FrameworkModality
        get() = when (this) {
            LANGUAGE, LANGUAGE_MODEL -> FrameworkModality.TEXT_TO_TEXT
            SPEECH_RECOGNITION -> FrameworkModality.VOICE_TO_TEXT
            SPEECH_SYNTHESIS -> FrameworkModality.TEXT_TO_VOICE
            VISION -> FrameworkModality.IMAGE_TO_TEXT
            IMAGE_GENERATION -> FrameworkModality.TEXT_TO_IMAGE
            MULTIMODAL -> FrameworkModality.MULTIMODAL
            AUDIO -> FrameworkModality.VOICE_TO_TEXT // Audio processing maps to voice-to-text
        }

    /**
     * Check if this category is compatible with a specific modality
     */
    fun isCompatible(modality: FrameworkModality): Boolean {
        return frameworkModality == modality ||
                (this == MULTIMODAL) || // Multimodal is compatible with most
                (modality == FrameworkModality.MULTIMODAL) // Multimodal modality matches most categories
    }

    /**
     * Whether this category typically requires context length
     */
    val requiresContextLength: Boolean
        get() = when (this) {
            LANGUAGE, LANGUAGE_MODEL, MULTIMODAL -> true
            else -> false
        }

    /**
     * Whether this category typically supports thinking/reasoning
     */
    val supportsThinking: Boolean
        get() = when (this) {
            LANGUAGE, LANGUAGE_MODEL, MULTIMODAL -> true
            else -> false
        }

    companion object {
        fun fromValue(value: String): ModelCategory? {
            return entries.find { it.value == value }
        }

        /**
         * Determine category from a framework
         * Matches iOS ModelCategory.from(framework:)
         */
        fun from(framework: InferenceFramework): ModelCategory {
            return when (framework) {
                InferenceFramework.WHISPER_KIT, InferenceFramework.WHISPER_CPP, InferenceFramework.OPEN_AI_WHISPER -> SPEECH_RECOGNITION
                InferenceFramework.SYSTEM_TTS -> SPEECH_SYNTHESIS
                InferenceFramework.LLAMA_CPP, InferenceFramework.LLAMACPP, InferenceFramework.MLX, InferenceFramework.MLC,
                InferenceFramework.EXECU_TORCH, InferenceFramework.PICO_LLM,
                InferenceFramework.FOUNDATION_MODELS, InferenceFramework.SWIFT_TRANSFORMERS -> LANGUAGE
                InferenceFramework.CORE_ML, InferenceFramework.TENSOR_FLOW_LITE,
                InferenceFramework.ONNX, InferenceFramework.MEDIA_PIPE -> MULTIMODAL
                // FluidAudio is for speaker diarization - categorize as audio
                InferenceFramework.FLUID_AUDIO -> AUDIO
                // Built-in is for VAD and other built-in algorithms - categorize as audio
                InferenceFramework.BUILT_IN -> AUDIO
                // Unknown/None default to multimodal
                InferenceFramework.NONE, InferenceFramework.UNKNOWN -> MULTIMODAL
            }
        }

        /**
         * Determine category from a FrameworkModality
         * Matches iOS ModelCategory.from(modality:)
         */
        fun from(modality: FrameworkModality): ModelCategory {
            return when (modality) {
                FrameworkModality.TEXT_TO_TEXT -> LANGUAGE
                FrameworkModality.VOICE_TO_TEXT -> SPEECH_RECOGNITION
                FrameworkModality.TEXT_TO_VOICE -> SPEECH_SYNTHESIS
                FrameworkModality.IMAGE_TO_TEXT -> VISION
                FrameworkModality.TEXT_TO_IMAGE -> IMAGE_GENERATION
                FrameworkModality.MULTIMODAL -> MULTIMODAL
            }
        }

        /**
         * Determine category from format and frameworks
         */
        fun from(format: ModelFormat, frameworks: List<InferenceFramework>): ModelCategory {
            // First check if we have framework hints
            frameworks.firstOrNull()?.let {
                return from(it)
            }

            // Otherwise guess from format
            return when (format) {
                ModelFormat.MLMODEL, ModelFormat.MLPACKAGE -> MULTIMODAL
                ModelFormat.GGUF, ModelFormat.GGML, ModelFormat.SAFETENSORS, ModelFormat.BIN -> LANGUAGE
                ModelFormat.TFLITE, ModelFormat.ONNX -> MULTIMODAL
                else -> LANGUAGE
            }
        }
    }
}
