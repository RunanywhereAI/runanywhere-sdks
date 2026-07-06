package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import androidx.compose.ui.graphics.vector.ImageVector
import com.runanywhere.runanywhereai.ui.theme.icons.Brand
import com.runanywhere.runanywhereai.ui.theme.icons.RACBrands
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.extensions.Models.displayName
import com.runanywhere.sdk.public.types.RAModelInfo

// Pure model -> display mappers. No Compose, no state.

enum class ConsumerModelGroup(val title: String, val footer: String) {
    CHAT_MODELS(
        "Chat Models",
        "Primary assistants for private chat. Download one to use it offline.",
    ),
    APPLE_BUILT_IN(
        "Built-in Models",
        "Models provided by the device or operating system need no download.",
    ),
    VISION_MODELS(
        "Vision Models",
        "Photo, camera, and multimodal understanding models.",
    ),
    VOICE_MODELS(
        "Voice Models",
        "Speech, dictation, and read-aloud models.",
    ),
    DOCUMENT_MODELS(
        "Document Models",
        "Embedding and answer models used by document Q&A.",
    ),
    OTHER(
        "Other Models",
        "Additional SDK entries available on this device.",
    ),
}

fun RAModelInfo.brand(): Brand {
    if (framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
    ) {
        return RACBrands.Foundation
    }
    val n = name.lowercase()
    return when {
        "llama" in n -> RACBrands.Meta
        "mistral" in n -> RACBrands.Mistral
        "qwen" in n -> RACBrands.Qwen
        "lfm" in n || "liquid" in n -> RACBrands.Liquid
        "whisper" in n -> RACBrands.Whisper
        else -> RACBrands.HuggingFace
    }
}

fun InferenceFramework.shortLabel(): String = when (this) {
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "Local"
    InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "ONNX"
    InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "Apple"
    InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> "System"
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> "NPU"
    InferenceFramework.INFERENCE_FRAMEWORK_GENIE -> "Genie"
    InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> "Sherpa"
    InferenceFramework.INFERENCE_FRAMEWORK_METALRT -> "Metal"
    InferenceFramework.INFERENCE_FRAMEWORK_COREML -> "Core ML"
    InferenceFramework.INFERENCE_FRAMEWORK_MLX -> "MLX"
    InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS -> "Piper"
    InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> "Fluid"
    InferenceFramework.INFERENCE_FRAMEWORK_TFLITE -> "TFLite"
    InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH -> "ExecuTorch"
    InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE -> "MediaPipe"
    InferenceFramework.INFERENCE_FRAMEWORK_MLC -> "MLC"
    InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM -> "Pico"
    InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS -> "Swift"
    InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> "Built-in"
    InferenceFramework.INFERENCE_FRAMEWORK_NONE -> "None"
    InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN -> "Unknown"
    else -> displayName
}

fun InferenceFramework.consumerBackendLabel(): String = when (this) {
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "Local Llama"
    InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "ONNX Runtime"
    InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "Apple Built-in"
    InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> "System Voice"
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> "Hexagon NPU"
    InferenceFramework.INFERENCE_FRAMEWORK_GENIE -> "Qualcomm Genie"
    InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> "Sherpa Voice"
    InferenceFramework.INFERENCE_FRAMEWORK_METALRT -> "Apple Metal"
    InferenceFramework.INFERENCE_FRAMEWORK_COREML -> "Core ML"
    InferenceFramework.INFERENCE_FRAMEWORK_MLX -> "MLX"
    InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS -> "Piper Voice"
    InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> "Fluid Audio"
    InferenceFramework.INFERENCE_FRAMEWORK_TFLITE -> "TensorFlow Lite"
    InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH -> "ExecuTorch"
    InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE -> "MediaPipe"
    InferenceFramework.INFERENCE_FRAMEWORK_MLC -> "MLC"
    InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM -> "Pico LLM"
    InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS -> "Swift Transformers"
    InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> "Built-in"
    InferenceFramework.INFERENCE_FRAMEWORK_NONE -> "No Backend"
    InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN -> "Unknown Backend"
    else -> displayName
}

fun InferenceFramework.backendIcon(): ImageVector = when (this) {
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> RACIcons.Outline.Stack
    InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> RACIcons.Outline.Activity
    InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> RACIcons.Filled.Bolt
    InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> RACIcons.Outline.Robot
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> RACIcons.Outline.Cpu
    InferenceFramework.INFERENCE_FRAMEWORK_GENIE -> RACIcons.Outline.Bolt
    InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> RACIcons.Outline.Microphone
    InferenceFramework.INFERENCE_FRAMEWORK_METALRT -> RACIcons.Outline.Bolt
    InferenceFramework.INFERENCE_FRAMEWORK_COREML -> RACIcons.Outline.Cpu
    InferenceFramework.INFERENCE_FRAMEWORK_MLX -> RACIcons.Outline.Cpu
    InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS -> RACIcons.Outline.Robot
    InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> RACIcons.Outline.Activity
    InferenceFramework.INFERENCE_FRAMEWORK_TFLITE,
    InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH,
    InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE,
    InferenceFramework.INFERENCE_FRAMEWORK_MLC,
    InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM,
    InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS,
    -> RACIcons.Outline.Stack
    InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> RACIcons.Outline.Check
    InferenceFramework.INFERENCE_FRAMEWORK_NONE -> RACIcons.Outline.Close
    InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN -> RACIcons.Outline.InfoCircle
    else -> RACIcons.Outline.Stack
}

fun RAModelInfo.consumerGroup(): ConsumerModelGroup = when {
    framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> ConsumerModelGroup.APPLE_BUILT_IN
    category == ModelCategory.MODEL_CATEGORY_LANGUAGE -> ConsumerModelGroup.CHAT_MODELS
    category == ModelCategory.MODEL_CATEGORY_MULTIMODAL ||
        category == ModelCategory.MODEL_CATEGORY_VISION -> ConsumerModelGroup.VISION_MODELS
    category == ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION ||
        category == ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS ||
        category == ModelCategory.MODEL_CATEGORY_AUDIO ||
        category == ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION -> ConsumerModelGroup.VOICE_MODELS
    category == ModelCategory.MODEL_CATEGORY_EMBEDDING -> ConsumerModelGroup.DOCUMENT_MODELS
    else -> ConsumerModelGroup.OTHER
}

fun RAModelInfo.capabilityLabels(): List<String> = buildList {
    when (category) {
        ModelCategory.MODEL_CATEGORY_LANGUAGE -> add("Chat")
        ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        ModelCategory.MODEL_CATEGORY_VISION,
        -> add("Vision")
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION -> add("Dictation")
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS -> add("Read aloud")
        ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION -> add("Voice")
        ModelCategory.MODEL_CATEGORY_EMBEDDING -> add("Documents")
        else -> Unit
    }
    if (supports_thinking) add("Thinking")
    if (supports_lora) add("LoRA-ready")
}.distinct()

fun formatModelSize(bytes: Long): String {
    if (bytes <= 0) return "—"
    val gb = bytes / 1_073_741_824.0
    return if (gb >= 1.0) "%.2f GB".format(gb) else "%.0f MB".format(bytes / 1_048_576.0)
}
