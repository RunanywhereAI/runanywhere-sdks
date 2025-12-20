package com.runanywhere.sdk.models.enums

import kotlinx.serialization.Serializable

/**
 * Supported inference frameworks/runtimes for executing models
 * Matches iOS InferenceFramework enum exactly
 */
@Serializable
enum class InferenceFramework(
    val value: String,
    val displayName: String,
) {
    CORE_ML("CoreML", "Core ML"),
    TENSOR_FLOW_LITE("TFLite", "TensorFlow Lite"),
    MLX("MLX", "MLX"),
    SWIFT_TRANSFORMERS("SwiftTransformers", "Swift Transformers"),
    ONNX("ONNX", "ONNX Runtime"),
    EXECU_TORCH("ExecuTorch", "ExecuTorch"),
    LLAMA_CPP("LlamaCpp", "llama.cpp"),
    FOUNDATION_MODELS("FoundationModels", "Foundation Models"),
    PICO_LLM("PicoLLM", "Pico LLM"),
    MLC("MLC", "MLC"),
    MEDIA_PIPE("MediaPipe", "MediaPipe"),
    WHISPER_KIT("WhisperKit", "WhisperKit"),
    OPEN_AI_WHISPER("OpenAIWhisper", "OpenAI Whisper"),
    SYSTEM_TTS("SystemTTS", "System TTS"),
    FLUID_AUDIO("FluidAudio", "FluidAudio"),

    // KMP-specific additions for extended use cases
    WHISPER_CPP("WhisperCpp", "Whisper.cpp"),
    BUILT_IN("built_in", "Built-in"), // For energy-based VAD and other built-in algorithms
    NONE("none", "None"),
    UNKNOWN("unknown", "Unknown"),
    ;

    companion object {
        fun fromValue(value: String): InferenceFramework? = entries.find { it.value == value }
    }

    /**
     * Whether this framework supports LLM (text-to-text)
     */
    val supportsLLM: Boolean
        get() =
            when (this) {
                LLAMA_CPP, MLX, CORE_ML, ONNX, FOUNDATION_MODELS, PICO_LLM, MLC -> true
                else -> false
            }

    /**
     * Whether this framework supports STT (speech-to-text)
     */
    val supportsSTT: Boolean
        get() =
            when (this) {
                WHISPER_KIT, OPEN_AI_WHISPER, MEDIA_PIPE, WHISPER_CPP -> true
                else -> false
            }

    /**
     * Whether this framework supports TTS (text-to-speech)
     */
    val supportsTTS: Boolean
        get() =
            when (this) {
                SYSTEM_TTS -> true
                else -> false
            }
}
