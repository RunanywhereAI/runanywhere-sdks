package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import com.runanywhere.runanywhereai.ui.theme.icons.Brand
import com.runanywhere.runanywhereai.ui.theme.icons.RACBrands
import com.runanywhere.sdk.public.extensions.Models.displayName
import com.runanywhere.sdk.public.types.RAModelInfo

// Pure model -> display mappers. No Compose, no state.

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
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "Fast"
    InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "ONNX"
    InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "Apple"
    InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> "System"
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> "NPU"
    else -> displayName
}

fun formatModelSize(bytes: Long): String {
    if (bytes <= 0) return "—"
    val gb = bytes / 1_073_741_824.0
    return if (gb >= 1.0) "%.2f GB".format(gb) else "%.0f MB".format(bytes / 1_048_576.0)
}
