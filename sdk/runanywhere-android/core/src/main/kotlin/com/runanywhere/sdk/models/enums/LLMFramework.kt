package com.runanywhere.sdk.models.enums

/**
 * Supported LLM frameworks - exact match with iOS
 */
enum class LLMFramework(val value: String, val displayName: String) {
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
    OPEN_AI_WHISPER("OpenAIWhisper", "OpenAI Whisper");

    companion object {
        fun fromValue(value: String): LLMFramework? {
            return values().find { it.value == value }
        }
    }
}
