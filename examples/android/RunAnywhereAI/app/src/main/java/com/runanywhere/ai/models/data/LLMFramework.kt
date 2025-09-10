package com.runanywhere.ai.models.data

enum class LLMFramework(
    val displayName: String,
    val description: String,
    val icon: String
) {
    LLAMACPP(
        displayName = "llama.cpp",
        description = "High-performance C++ inference",
        icon = "cpu"
    ),
    ONNX_RUNTIME(
        displayName = "ONNX Runtime",
        description = "Cross-platform ML inference",
        icon = "memory"
    ),
    TENSORFLOW_LITE(
        displayName = "TensorFlow Lite",
        description = "Mobile-optimized ML framework",
        icon = "android"
    ),
    FOUNDATION_MODELS(
        displayName = "Foundation Models",
        description = "Built-in system models",
        icon = "phone_android"
    ),
    WHISPER_CPP(
        displayName = "Whisper.cpp",
        description = "Speech recognition models",
        icon = "mic"
    ),
    CUSTOM(
        displayName = "Custom",
        description = "Custom inference engine",
        icon = "extension"
    )
}
