package com.runanywhere.sdk.models.enums

/**
 * Defines the category/type of a model based on its input/output modality
 * This aligns with FrameworkModality for consistency across the SDK
 */
enum class ModelCategory(
    val value: String,
    val displayName: String,
    val iconName: String
) {
    LANGUAGE("language", "Language Model", "text_bubble"),
    SPEECH_RECOGNITION("speech-recognition", "Speech Recognition", "mic"),
    SPEECH_SYNTHESIS("speech-synthesis", "Text-to-Speech", "speaker_wave_2"),
    VISION("vision", "Vision Model", "photo_badge_arrow_down"),
    IMAGE_GENERATION("image-generation", "Image Generation", "photo_badge_plus"),
    MULTIMODAL("multimodal", "Multimodal", "sparkles"),
    AUDIO("audio", "Audio Processing", "waveform");

    /**
     * Whether this category typically requires context length
     */
    val requiresContextLength: Boolean
        get() = when (this) {
            LANGUAGE, MULTIMODAL -> true
            else -> false
        }

    /**
     * Whether this category typically supports thinking/reasoning
     */
    val supportsThinking: Boolean
        get() = when (this) {
            LANGUAGE, MULTIMODAL -> true
            else -> false
        }

    companion object {
        fun fromValue(value: String): ModelCategory? {
            return values().find { it.value == value }
        }

        /**
         * Determine category from a framework
         */
        fun from(framework: LLMFramework): ModelCategory {
            return when (framework) {
                LLMFramework.WHISPER_KIT, LLMFramework.WHISPER_CPP, LLMFramework.OPEN_AI_WHISPER -> SPEECH_RECOGNITION
                LLMFramework.LLAMA_CPP, LLMFramework.MLX, LLMFramework.MLC,
                LLMFramework.EXECU_TORCH, LLMFramework.PICO_LLM,
                LLMFramework.FOUNDATION_MODELS, LLMFramework.SWIFT_TRANSFORMERS -> LANGUAGE

                LLMFramework.CORE_ML, LLMFramework.TENSOR_FLOW_LITE,
                LLMFramework.ONNX, LLMFramework.MEDIA_PIPE -> MULTIMODAL
            }
        }

        /**
         * Determine category from format and frameworks
         */
        fun from(format: ModelFormat, frameworks: List<LLMFramework>): ModelCategory {
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
