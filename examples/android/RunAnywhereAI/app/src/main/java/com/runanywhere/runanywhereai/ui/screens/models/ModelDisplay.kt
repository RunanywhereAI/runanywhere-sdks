package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import androidx.compose.ui.graphics.vector.ImageVector
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.extensions.Models.displayName
import com.runanywhere.sdk.public.types.RAModelInfo

// Pure model -> display mappers. No Compose, no state. Family/maker classification is
// not here — it lives in ModelTaxonomy.kt, the single source of truth.

private val privateHfTags = setOf("private", "requires-hf-auth", "hf-auth", "gated")

fun InferenceFramework.shortLabel(): String = when (this) {
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "Llama CPP"
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

// Short, tidy label used on the backend filter chips. NPU/QHexRT stays prominent.
fun InferenceFramework.filterLabel(): String = when (this) {
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "Llama.cpp"
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> "NPU"
    InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> "Sherpa"
    InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "ONNX"
    InferenceFramework.INFERENCE_FRAMEWORK_MLX -> "MLX"
    else -> shortLabel()
}

fun RAModelInfo.requiresHfAuth(): Boolean {
    val tags = metadata?.tags.orEmpty().map { it.lowercase() }
    return (framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT &&
        QHexRT.modelRequiresHfAuth(id)) || tags.any { it in privateHfTags }
}

// Effective on-disk / in-memory footprint used for sizing and consumer tags.
fun RAModelInfo.effectiveBytes(): Long = when {
    download_size_bytes > 0L -> download_size_bytes
    (memory_required_bytes ?: 0L) > 0L -> memory_required_bytes ?: 0L
    else -> 0L
}

// Rough "intelligence" hint derived from parameter count (parsed from the name)
// with a byte-size fallback. Used INTERNALLY only (recommendation + variant order);
// never shown as a raw label on cards.
enum class ModelIntelligence { LITE, BALANCED, SMART, GENIUS }

fun RAModelInfo.intelligence(): ModelIntelligence {
    val params = estimatedParamsBillions()
    if (params != null) {
        return when {
            params < 0.7 -> ModelIntelligence.LITE
            params < 2.0 -> ModelIntelligence.BALANCED
            params < 5.0 -> ModelIntelligence.SMART
            else -> ModelIntelligence.GENIUS
        }
    }
    // No parseable param count — fall back to footprint.
    val mb = effectiveBytes() / 1_048_576.0
    return when {
        mb < 500 -> ModelIntelligence.LITE
        mb < 2_000 -> ModelIntelligence.BALANCED
        mb < 6_000 -> ModelIntelligence.SMART
        else -> ModelIntelligence.GENIUS
    }
}

// Parses a parameter count in billions from tokens like "0.6b", "1.5b", "350m", "7b".
private fun RAModelInfo.estimatedParamsBillions(): Double? {
    val haystack = "$id $name".lowercase()
    Regex("""(\d+(?:\.\d+)?)\s*b\b""").find(haystack)?.let {
        return it.groupValues[1].toDoubleOrNull()
    }
    Regex("""(\d+(?:\.\d+)?)\s*m\b""").find(haystack)?.let {
        return it.groupValues[1].toDoubleOrNull()?.div(1000.0)
    }
    return null
}

// The single "feel" word shown on every card. Derived from intelligence but collapsed
// to three consumer-friendly buckets — no Lite/Genius, no raw parameter counts.
enum class ModelFeel(val label: String) { FAST("Fast"), BALANCED("Balanced"), SMART("Smart") }

fun RAModelInfo.feel(): ModelFeel = when (intelligence()) {
    ModelIntelligence.LITE -> ModelFeel.FAST
    ModelIntelligence.BALANCED -> ModelFeel.BALANCED
    ModelIntelligence.SMART, ModelIntelligence.GENIUS -> ModelFeel.SMART
}

/**
 * Semantic kind so the UI can colour pills consistently and pick the right one per
 * surface. [MODALITY] restates what the model is for, which is only worth saying in a
 * list that mixes modalities — inside a single-modality picker it is noise, so the
 * family and variant rows show [CAPABILITY] or [FEEL] instead.
 */
enum class ConsumerTagKind { FEEL, MODALITY, CAPABILITY }

data class ConsumerTag(val label: String, val kind: ConsumerTagKind)

// AT MOST two clean, consumer-facing tags per model: a feel tag, plus one notable
// modality or capability tag when applicable. No quantization, size, context length, or
// backend terms ever appear here — those stay internal to recommendation / ordering.
fun RAModelInfo.consumerTags(): List<ConsumerTag> = buildList {
    add(ConsumerTag(feel().label, ConsumerTagKind.FEEL))
    notableTag()?.let { add(it) }
}

// The single most notable thing to say about a model beyond its feel, or null when
// nothing stands out. What it handles (vision/voice/documents) wins over how it behaves
// (tools/thinking), because the two never both fit on one row.
private fun RAModelInfo.notableTag(): ConsumerTag? {
    val modality = when (category) {
        ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        ModelCategory.MODEL_CATEGORY_VISION,
        -> "Vision"
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        ModelCategory.MODEL_CATEGORY_AUDIO,
        -> "Voice"
        ModelCategory.MODEL_CATEGORY_EMBEDDING -> "Documents"
        else -> null
    }
    if (modality != null) return ConsumerTag(modality, ConsumerTagKind.MODALITY)
    if (isToolCallingModel()) return ConsumerTag("Great for tools", ConsumerTagKind.CAPABILITY)
    if (supports_thinking) return ConsumerTag("Thinks", ConsumerTagKind.CAPABILITY)
    return null
}

// Tool-oriented chat models: LiquidAI "tool" builds and every NVIDIA family are
// trained/tuned for function calling. Maker comes from the taxonomy, never a local
// string match.
private fun RAModelInfo.isToolCallingModel(): Boolean =
    "tool" in "$id $name".lowercase() || maker() == ModelMaker.NVIDIA

// Friendly variant label used inside a family's variant list — "Smaller · faster" vs
// "Larger · smarter" — instead of quant strings. Ordered by footprint upstream.
fun RAModelInfo.variantFeelLabel(): String = when (feel()) {
    ModelFeel.FAST -> "Smaller · faster"
    ModelFeel.BALANCED -> "Balanced"
    ModelFeel.SMART -> "Larger · smarter"
}

fun formatModelSize(bytes: Long): String {
    if (bytes <= 0) return "—"
    val gb = bytes / 1_073_741_824.0
    return if (gb >= 1.0) "%.2f GB".format(gb) else "%.0f MB".format(bytes / 1_048_576.0)
}

// Quant / precision tokens stripped from display titles. Word-bounded so parameter
// counts like "0.5B" or family names like "LFM2" are never touched.
private val quantTokenRegex = Regex("""(?i)\b(Q\d(_K(_[MS])?|_0)?|FP16|F16|INT8|[458]BIT|DWQ)\b""")

// Backend markers such as "(HNPU)", "(HNPU, fully-on-NPU)", "(Sherpa-ONNX)" and "(CPU)".
// The backend badge on every row already says which runtime executes the model, so the
// suffix is pure noise. Meaningful parentheticals like "(Experimental)" survive.
private val backendMarkerRegex = Regex("""(?i)\s*\((?:HNPU|ONNX|CPU|Sherpa-ONNX)\b[^)]*\)""")

// Vendor / marker noise removed from display titles; the family card's maker line and
// brand mark carry that instead. "Instruct" is implied for consumer chat models.
private val titleNoise = listOf("NVIDIA", "LiquidAI", "Instruct")

// Clean, consumer-facing row title: family + parameter size (e.g. "LFM2 1.2B Tool",
// "Qwen3 4B") with quant suffixes and vendor prefixes stripped from the raw name.
fun RAModelInfo.displayTitle(): String {
    var title = backendMarkerRegex.replace(name, "")
    titleNoise.forEach { title = title.replace(it, "", ignoreCase = true) }
    title = quantTokenRegex.replace(title, "")
    return title.replace(Regex("""\s+"""), " ").trim().trimEnd('-', '·', ',').trim()
}

// Download-size label shown on every model row — the user always sees the cost.
fun RAModelInfo.sizeLabel(): String {
    val bytes = effectiveBytes()
    if (bytes > 0) return formatModelSize(bytes)
    return if (requiresHfAuth()) "Size varies" else "Size unknown"
}
