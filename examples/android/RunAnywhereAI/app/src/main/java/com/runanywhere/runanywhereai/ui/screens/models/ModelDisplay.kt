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
    LORA_ADAPTERS(
        "LoRA Adapters",
        "Style, task, and domain adapters that attach to compatible chat models.",
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
    InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> "Sherpa"
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
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "Llama CPP"
    InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "ONNX Runtime"
    InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "Apple Built-in"
    InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> "System Voice"
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> "Hexagon NPU"
    InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> "Sherpa Voice"
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
    InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> RACIcons.Outline.Microphone
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
    isLoraAdapterEntry() -> ConsumerModelGroup.LORA_ADAPTERS
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

private fun RAModelInfo.isLoraAdapterEntry(): Boolean =
    id.startsWith("lora-adapter:") ||
        metadata?.tags.orEmpty().any { tag ->
            tag.equals("lora-adapter", ignoreCase = true) ||
                tag.equals("lora", ignoreCase = true)
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

fun RAModelInfo.quantizationLabel(): String {
    val haystack = listOf(id, name, download_url).joinToString(" ").lowercase()
    val known = listOf(
        "q4_k_m" to "Q4_K_M",
        "q4_k_s" to "Q4_K_S",
        "q5_k_m" to "Q5_K_M",
        "q6_k" to "Q6_K",
        "q8_0" to "Q8_0",
        "4bit" to "4bit",
        "5bit" to "5bit",
        "8bit" to "8bit",
        "f16" to "F16",
        "fp16" to "FP16",
        "dwq" to "DWQ",
    )
    return known.firstOrNull { haystack.contains(it.first) }?.second ?: "Default"
}

enum class ModelBackendFilter(val title: String) {
    ALL("All"),
    MLX("MLX"),
    LLAMA_CPP("Llama CPP"),
    QHEXRT("QHexRT"),
    ONNX("ONNX"),
    SHERPA("Sherpa"),
    APPLE("Apple"),
}

fun ModelBackendFilter.matches(model: RAModelInfo): Boolean = when (this) {
    ModelBackendFilter.ALL -> true
    ModelBackendFilter.MLX -> model.framework == InferenceFramework.INFERENCE_FRAMEWORK_MLX
    ModelBackendFilter.LLAMA_CPP -> model.framework == InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
    ModelBackendFilter.QHEXRT -> model.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT
    ModelBackendFilter.ONNX -> model.framework == InferenceFramework.INFERENCE_FRAMEWORK_ONNX
    ModelBackendFilter.SHERPA -> model.framework == InferenceFramework.INFERENCE_FRAMEWORK_SHERPA
    ModelBackendFilter.APPLE -> model.framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        model.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
}

enum class ModelGroupFilter(val title: String) {
    ALL("All"),
    CHAT("Chat"),
    VISION("Vision"),
    VOICE("Voice"),
    DOCUMENTS("Documents"),
    ADAPTERS("Adapters"),
}

fun ModelGroupFilter.matches(model: RAModelInfo): Boolean = when (this) {
    ModelGroupFilter.ALL -> true
    ModelGroupFilter.CHAT -> model.consumerGroup() == ConsumerModelGroup.CHAT_MODELS ||
        model.consumerGroup() == ConsumerModelGroup.APPLE_BUILT_IN
    ModelGroupFilter.VISION -> model.consumerGroup() == ConsumerModelGroup.VISION_MODELS
    ModelGroupFilter.VOICE -> model.consumerGroup() == ConsumerModelGroup.VOICE_MODELS
    ModelGroupFilter.DOCUMENTS -> model.consumerGroup() == ConsumerModelGroup.DOCUMENT_MODELS
    ModelGroupFilter.ADAPTERS -> model.consumerGroup() == ConsumerModelGroup.LORA_ADAPTERS
}

enum class ModelQuantizationFilter(val title: String) {
    ALL("All"),
    Q4("Q4"),
    Q5("Q5"),
    Q6("Q6"),
    Q8("Q8"),
    FOUR_BIT("4bit"),
    FIVE_BIT("5bit"),
    EIGHT_BIT("8bit"),
    F16("F16"),
}

fun ModelQuantizationFilter.matches(model: RAModelInfo): Boolean {
    val label = model.quantizationLabel().lowercase()
    return when (this) {
        ModelQuantizationFilter.ALL -> true
        ModelQuantizationFilter.Q4 -> "q4" in label
        ModelQuantizationFilter.Q5 -> "q5" in label
        ModelQuantizationFilter.Q6 -> "q6" in label
        ModelQuantizationFilter.Q8 -> "q8" in label
        ModelQuantizationFilter.FOUR_BIT -> "4bit" in label
        ModelQuantizationFilter.FIVE_BIT -> "5bit" in label
        ModelQuantizationFilter.EIGHT_BIT -> "8bit" in label
        ModelQuantizationFilter.F16 -> "f16" in label
    }
}

fun formatModelSize(bytes: Long): String {
    if (bytes <= 0) return "—"
    val gb = bytes / 1_073_741_824.0
    return if (gb >= 1.0) "%.2f GB".format(gb) else "%.0f MB".format(bytes / 1_048_576.0)
}
