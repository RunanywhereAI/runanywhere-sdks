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

private val privateHfTags = setOf("private", "requires-hf-auth", "hf-auth", "gated")

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

// A consumer-facing "family" — a group of related model variants (e.g. Qwen3, LFM2,
// Whisper). The picker shows one card per family; tapping expands its variants.
data class ModelFamily(val key: String, val title: String, val tagline: String)

// Ordered family matchers. First match wins; each entry maps id/name substrings to a
// friendly family. Kept as a pure list so families are easy to extend without touching
// UI. HNPU (on-device accelerated) families are distinguished from their GGUF cousins
// by the "_HNPU"/"(HNPU)" marker so the two never collapse into one card.
private data class FamilyMatcher(
    val key: String,
    val title: String,
    val tagline: String,
    val matches: (String) -> Boolean,
)

private fun containsAll(vararg needles: String): (String) -> Boolean =
    { h -> needles.all { it in h } }

private fun containsAny(vararg needles: String): (String) -> Boolean =
    { h -> needles.any { it in h } }

private val familyMatchers: List<FamilyMatcher> = listOf(
    // On-device accelerated (HNPU) families first — the marker keeps them separate.
    FamilyMatcher("qwen3-npu", "Qwen3 (On-device)", "Accelerated Qwen chat", containsAll("qwen3", "hnpu")),
    FamilyMatcher("lfm2-npu", "LFM2 (On-device)", "Accelerated Liquid chat", containsAll("lfm2", "hnpu")),
    FamilyMatcher("llama-npu", "Llama (On-device)", "Accelerated Meta chat", containsAll("llama", "hnpu")),
    FamilyMatcher("gemma-npu", "Gemma (On-device)", "Accelerated Google chat", containsAll("gemma", "hnpu")),
    FamilyMatcher("deepseek-npu", "DeepSeek (On-device)", "Accelerated reasoning", containsAll("deepseek", "hnpu")),
    FamilyMatcher("nemotron-npu", "Nemotron (On-device)", "Accelerated NVIDIA models", containsAll("nemotron", "hnpu")),
    FamilyMatcher("qwenvl-npu", "Qwen-VL (On-device)", "Accelerated vision chat", containsAll("qwen3_vl", "hnpu")),
    FamilyMatcher("whisper-npu", "Whisper (On-device)", "Accelerated speech-to-text", containsAll("whisper", "hnpu")),
    FamilyMatcher("kokoro-npu", "Kokoro (On-device)", "Accelerated read-aloud", containsAll("kokoro", "hnpu")),
    FamilyMatcher("kitten-npu", "Kitten (On-device)", "Accelerated read-aloud", containsAll("kitten", "hnpu")),
    FamilyMatcher("embed-npu", "On-device Embeddings", "Accelerated document search", containsAll("embed", "hnpu")),

    // Standard on-device families.
    FamilyMatcher("qwen3", "Qwen3", "Fast, capable chat", containsAny("qwen3", "qwen 3")),
    FamilyMatcher("qwen25", "Qwen2.5", "Reliable everyday chat", containsAny("qwen2.5", "qwen 2.5")),
    FamilyMatcher("qwen2vl", "Qwen2-VL", "Chat about photos", containsAny("qwen2-vl", "qwen2.5-vl")),
    FamilyMatcher("lfm2", "LFM2", "Efficient Liquid chat", containsAny("lfm2")),
    FamilyMatcher("smol", "SmolLM / SmolVLM", "Tiny, quick assistants", containsAny("smol")),
    FamilyMatcher("llama", "Llama", "Meta's open chat", containsAny("llama")),
    FamilyMatcher("mistral", "Mistral", "Balanced open chat", containsAny("mistral")),
    FamilyMatcher("gemma", "Gemma", "Google's open chat", containsAny("gemma")),
    FamilyMatcher("whisper", "Whisper", "Speech-to-text", containsAny("whisper")),
    FamilyMatcher("piper", "Piper", "Natural read-aloud", containsAny("piper")),
    FamilyMatcher("minilm", "MiniLM", "Document search", containsAny("minilm")),
    FamilyMatcher("silero", "Silero", "Detects speech", containsAny("silero")),
)

// Pure family derivation from id + name. Falls back to a category-based family so every
// model lands somewhere sensible.
fun RAModelInfo.family(): ModelFamily {
    val haystack = "$id $name".lowercase()
    familyMatchers.firstOrNull { it.matches(haystack) }?.let {
        return ModelFamily(it.key, it.title, it.tagline)
    }
    return when (consumerGroup()) {
        ConsumerModelGroup.VISION_MODELS -> ModelFamily("other-vision", "Vision Models", "Chat about photos")
        ConsumerModelGroup.VOICE_MODELS -> ModelFamily("other-voice", "Voice Models", "Speech and read-aloud")
        ConsumerModelGroup.DOCUMENT_MODELS -> ModelFamily("other-docs", "Document Models", "Search your documents")
        ConsumerModelGroup.LORA_ADAPTERS -> ModelFamily("other-lora", "Adapters", "Fine-tune a chat model")
        ConsumerModelGroup.CHAT_MODELS,
        ConsumerModelGroup.APPLE_BUILT_IN -> ModelFamily("other-chat", "Other Chat Models", "More assistants")
        ConsumerModelGroup.OTHER -> ModelFamily("other", "Other Models", "Additional models")
    }
}


fun RAModelInfo.requiresHfAuth(): Boolean {
    val tags = metadata?.tags.orEmpty().map { it.lowercase() }
    return tags.any { it in privateHfTags } ||
        framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT &&
        download_url.contains("_HNPU", ignoreCase = true)
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

// Semantic kind so the UI can color pills consistently across the picker.
enum class ConsumerTagKind { FEEL, CAPABILITY }

data class ConsumerTag(val label: String, val kind: ConsumerTagKind)

// AT MOST two clean, consumer-facing tags per card: a feel tag, plus one notable
// capability tag when applicable. No quantization, size, context length, or backend
// terms ever appear here — those stay internal to recommendation / variant ordering.
fun RAModelInfo.consumerTags(): List<ConsumerTag> = buildList {
    add(ConsumerTag(feel().label, ConsumerTagKind.FEEL))
    notableCapability()?.let { add(ConsumerTag(it, ConsumerTagKind.CAPABILITY)) }
}

// The single most notable capability, or null when nothing stands out. Capability
// (vision/voice/documents) wins over behavioral hints (tools/thinking).
private fun RAModelInfo.notableCapability(): String? {
    when (category) {
        ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        ModelCategory.MODEL_CATEGORY_VISION,
        -> return "Vision"
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        ModelCategory.MODEL_CATEGORY_AUDIO,
        -> return "Voice"
        ModelCategory.MODEL_CATEGORY_EMBEDDING -> return "Documents"
        else -> Unit
    }
    if (isToolCallingModel()) return "Great for tools"
    if (supports_thinking) return "Thinks"
    return null
}

// Tool-oriented chat models: LiquidAI "tool" builds and NVIDIA Nemotron families
// are trained/tuned for function calling; also catch any id/name flagged "tool".
private fun RAModelInfo.isToolCallingModel(): Boolean {
    val haystack = "$id $name".lowercase()
    return "tool" in haystack || "nemotron" in haystack
}

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
private val quantTokenRegex = Regex("""(?i)\b(Q\d(_K(_[MS])?|_0)?|FP16|F16|[458]BIT|DWQ)\b""")

// Vendor / marker noise removed from display titles; the brand icon and backend badge
// carry that information instead. "Instruct" is implied for consumer chat models.
private val titleNoise = listOf("(HNPU)", "(ONNX)", "LiquidAI", "Instruct")

// Clean, consumer-facing row title: family + parameter size (e.g. "LFM2 1.2B Tool",
// "Qwen3 4B") with quant suffixes and vendor prefixes stripped from the raw name.
fun RAModelInfo.displayTitle(): String {
    var title = name
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
