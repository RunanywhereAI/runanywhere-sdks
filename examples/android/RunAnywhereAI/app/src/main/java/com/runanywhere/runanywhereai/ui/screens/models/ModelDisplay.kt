package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import androidx.compose.ui.graphics.vector.ImageVector
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

/**
 * What to call the runtime on a consumer surface, where the reader did not ask
 * which library is executing anything.
 *
 * Distinct from [shortLabel] on purpose, and the split mirrors iOS: a model row
 * in the picker is a spec sheet, so naming the engine there is informative
 * ([shortLabel] / iOS `consumerBackendShortLabel` -> `consumerBackendBadgeLabel`),
 * while the chat header sits above every conversation and is read by someone who
 * only wants to know *where* their words are going. "Llama CPP" answers a
 * question nobody asked; "Local" answers the one they have.
 */
fun InferenceFramework.consumerBackendShortLabel(): String = when (this) {
    // Not "Llama CPP": the fact worth stating is that the model runs here, on
    // this device, which is the product's entire premise.
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "Local"
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> "NPU"
    InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "Apple"
    InferenceFramework.INFERENCE_FRAMEWORK_COREML -> "NeuRT"
    else -> shortLabel()
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

/**
 * The badge glyph for a backend, chosen by *what kind of runtime it is* — a general LLM
 * framework, a compute-graph runtime, an audio engine, or accelerator silicon.
 *
 * Every arm here has to be legible next to every other arm, because these badges appear
 * side by side in the model list. Four of them used to collide: ONNX and Fluid Audio both
 * drew the signal trace the VAD screen used for speech detection, and QHexRT, CoreML and
 * MLX all drew the same chip the device card used for "Chip" and the Benchmarks row used
 * for itself. Accelerated backends now share [RACIcons.Outline.Cpu] *only* with each other
 * — which is correct, since "runs on an accelerator" is genuinely one meaning — while the
 * device's own silicon row and the benchmark entry moved off it entirely.
 */
fun InferenceFramework.backendIcon(): ImageVector = when (this) {
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> RACIcons.Outline.Stack
    // A compute graph, which is literally what an ONNX file holds.
    InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> RACIcons.Outline.Graph
    InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> RACIcons.Filled.Bolt
    InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> RACIcons.Outline.Robot
    // Accelerator-backed runtimes. One glyph, one meaning: "this runs on dedicated silicon."
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    InferenceFramework.INFERENCE_FRAMEWORK_COREML,
    InferenceFramework.INFERENCE_FRAMEWORK_MLX,
    -> RACIcons.Outline.Cpu
    // Speech engines: the subject is the audio signal, not the microphone that captured it.
    InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
    InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO,
    -> RACIcons.Outline.Waveform
    InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS -> RACIcons.Outline.Robot
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

// MODEL_CATEGORY_IMAGE_GENERATION spans both text-to-image and image-to-image (LaMa
// inpainting), and RAModelInfo carries no diffusion-mode field, so category alone cannot
// tell them apart. Surfaces that generate an image FROM A PROMPT must filter on this;
// matching the bare category silently resolves to an inpainting model whenever the
// text-to-image row is unavailable, which then fails at generate with NOT_SUPPORTED.
private val textToImageModelIds = setOf("cosmos3_edge_diffusion")

fun RAModelInfo.servesTextToImage(): Boolean =
    category == ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION && id in textToImageModelIds

// Nemotron OCR / Parse are cataloged as MULTIMODAL (same VLM lifecycle as InternVL)
// but they are detector+recognizer document pipelines, not caption VLMs. Keep them
// out of the Vision picker and route them through the Document OCR surface.
private val documentOcrModelIds = setOf(
    "nemotron_ocr",
    "nemotron_ocr_v1",
    "nemotron_parse",
)

fun RAModelInfo.isDocumentOcrModel(): Boolean =
    id in documentOcrModelIds ||
        (category == ModelCategory.MODEL_CATEGORY_MULTIMODAL &&
            (id.contains("_ocr", ignoreCase = true) ||
                id.endsWith("_parse", ignoreCase = true) ||
                (name.contains("OCR", ignoreCase = true) &&
                    name.contains("Nemotron", ignoreCase = true))))

fun RAModelInfo.requiresHfAuth(): Boolean {
    val tags = metadata?.tags.orEmpty().map { it.lowercase() }
    return tags.any { it in privateHfTags }
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

private val paramsBillionsRegex = Regex("""(\d+(?:\.\d+)?)\s*b\b""")
private val paramsMillionsRegex = Regex("""(\d+(?:\.\d+)?)\s*m\b""")

/**
 * Parameter count in billions, parsed from tokens like "0.6b", "1.5b", "350m", "7b".
 *
 * The NAME is read first and the id is only a fallback, because an id cannot contain a
 * dot — a QNN bundle is a directory — so the NPU catalog spells decimals with an
 * underscore: `qwen3_0_6b`. Searching that yields the token "6b" and reports SIX billion
 * parameters, which labelled the 0.6B NPU row "Smart" while the identical llama.cpp row
 * read "Fast", side by side in the picker. The name ("Qwen3 0.6B") already carries the
 * decimal, and every LLM in the catalog has one, so this path is the accurate one.
 *
 * Restoring the underscores instead is what it looks like it should do and is wrong:
 * `lfm2_5_350m` would become "lfm2.5.350m", whose leftmost match is "5.350" — five
 * million parameters for a 350M model. Version numbers and parameter counts are not
 * distinguishable once both are dotted.
 */
private fun RAModelInfo.estimatedParamsBillions(): Double? =
    parseParamsBillions(name.lowercase()) ?: parseParamsBillions(id.lowercase())

private fun parseParamsBillions(haystack: String): Double? {
    paramsBillionsRegex.find(haystack)?.let {
        return it.groupValues[1].toDoubleOrNull()
    }
    paramsMillionsRegex.find(haystack)?.let {
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
        -> if (isDocumentOcrModel()) "OCR" else "Vision"
        ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION -> "Segmentation"
        ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION -> "Image gen"
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

// Tool-oriented chat models: LiquidAI "tool" builds and every NVIDIA model are
// trained/tuned for function calling. Org comes from the taxonomy, never a local
// string match.
private fun RAModelInfo.isToolCallingModel(): Boolean =
    "tool" in "$id $name".lowercase() || org() == ModelOrg.NVIDIA

// Friendly size/feel label on each model row — "Smaller · faster" vs
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
