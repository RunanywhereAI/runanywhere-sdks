package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.runanywhereai.ui.theme.icons.Brand
import com.runanywhere.runanywhereai.ui.theme.icons.RACBrands
import com.runanywhere.sdk.public.types.RAModelInfo

/**
 * The single source of truth for model identity in the picker.
 *
 * Everything the user sees about where a model belongs — its maker, the family card it
 * shares with its siblings, and the brand mark drawn beside it — is derived from the one
 * [familySpecs] table below. No other file may match on model ids or names.
 *
 * A family deliberately spans backends: the QHexRT (NPU) and llama.cpp builds of the same
 * series are ONE family with two variants, told apart by the backend badge on each variant
 * row, instead of two near-identical "Llama" / "Llama (On-device)" cards.
 */

/** Coarse capability bucket. Declaration order is the picker's family ordering. */
enum class ModelCategoryBucket(val fallbackTagline: String) {
    CHAT("On-device assistant"),
    VISION("Understands images"),
    VOICE("Speech and voice"),
    EMBEDDING("Document search"),
    OTHER("On-device model"),
}

fun RAModelInfo.categoryBucket(): ModelCategoryBucket = when (category) {
    ModelCategory.MODEL_CATEGORY_LANGUAGE -> ModelCategoryBucket.CHAT
    ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    ModelCategory.MODEL_CATEGORY_VISION,
    ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
    -> ModelCategoryBucket.VISION
    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    ModelCategory.MODEL_CATEGORY_AUDIO,
    ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    -> ModelCategoryBucket.VOICE
    ModelCategory.MODEL_CATEGORY_EMBEDDING -> ModelCategoryBucket.EMBEDDING
    else -> ModelCategoryBucket.OTHER
}

/** The organisation behind a family. Its [Brand] carries the display name, mark and colour. */
enum class ModelMaker(val brand: Brand) {
    NVIDIA(RACBrands.Nvidia),
    META(RACBrands.Meta),
    ALIBABA(RACBrands.Alibaba),
    GOOGLE(RACBrands.Google),
    MICROSOFT(RACBrands.Microsoft),
    DEEPSEEK(RACBrands.DeepSeek),
    LIQUID(RACBrands.Liquid),
    MISTRAL(RACBrands.Mistral),
    PRISM(RACBrands.Prism),
    OPENAI(RACBrands.OpenAI),
    HUGGING_FACE(RACBrands.HuggingFace),
    APPLE(RACBrands.Apple),
    OPEN_SOURCE(RACBrands.OpenSource),
    ;

    val displayName: String get() = brand.label
}

/**
 * A consumer-facing family — one series of related model variants (Llama, Bonsai,
 * Parakeet). The picker shows one card per family; tapping it expands its variants.
 */
data class ModelFamily(
    val key: String,
    val title: String,
    val tagline: String,
    val maker: ModelMaker,
)

/**
 * One row of the classification table: id/name substrings that place a model into a family
 * within a single [bucket]. Bucket scoping is what stops a chat brand token pulling an
 * embedding or vision model into a chat family ("Llama Embed Nemotron" is not a Llama chat
 * model). Within a bucket the FIRST match wins, so specific tokens precede generic ones.
 */
private data class FamilySpec(
    val key: String,
    val title: String,
    val tagline: String,
    val maker: ModelMaker,
    val bucket: ModelCategoryBucket,
    val tokens: List<String>,
) {
    fun matches(haystack: String, bucket: ModelCategoryBucket): Boolean =
        this.bucket == bucket && tokens.any { it in haystack }

    fun toFamily(): ModelFamily = ModelFamily(key, title, tagline, maker)
}

private fun spec(
    key: String,
    title: String,
    tagline: String,
    maker: ModelMaker,
    bucket: ModelCategoryBucket,
    vararg tokens: String,
) = FamilySpec(key, title, tagline, maker, bucket, tokens.toList())

private val CHAT = ModelCategoryBucket.CHAT
private val VISION = ModelCategoryBucket.VISION
private val VOICE = ModelCategoryBucket.VOICE
private val EMBEDDING = ModelCategoryBucket.EMBEDDING

private val familySpecs: List<FamilySpec> = listOf(
    // ── Chat ── "deepseek" precedes "qwen" (R1 distills are Qwen-based) and "nemotron"
    // precedes "llama" (the Nano checkpoints are Llama-based but ship as NVIDIA models).
    spec("deepseek-r1", "DeepSeek R1", "Distilled reasoning", ModelMaker.DEEPSEEK, CHAT, "deepseek"),
    spec("nemoguard", "NemoGuard", "Content-safety guardrails", ModelMaker.NVIDIA, CHAT, "nemoguard"),
    spec("nemotron", "Nemotron", "NVIDIA's tool-savvy assistants", ModelMaker.NVIDIA, CHAT, "nemotron"),
    spec("cosmos3-edge", "Cosmos3-Edge", "Omnimodal edge assistant", ModelMaker.NVIDIA, CHAT, "cosmos3"),
    spec("bonsai", "Bonsai", "1-bit compact reasoning", ModelMaker.PRISM, CHAT, "bonsai"),
    spec("phi", "Phi", "Microsoft's small models", ModelMaker.MICROSOFT, CHAT, "phi"),
    spec("gemma", "Gemma", "Google's compact assistants", ModelMaker.GOOGLE, CHAT, "gemma"),
    spec("llama", "Llama", "Meta's open assistants", ModelMaker.META, CHAT, "llama"),
    spec("qwen3-vl-text", "Qwen3-VL", "Vision series, text path", ModelMaker.ALIBABA, CHAT, "qwen3_vl", "qwen3-vl"),
    spec("qwen3", "Qwen3", "Fast, capable chat", ModelMaker.ALIBABA, CHAT, "qwen3"),
    spec("qwen2", "Qwen2.5", "Reliable everyday chat", ModelMaker.ALIBABA, CHAT, "qwen2"),
    spec("lfm2", "LFM2", "Efficient Liquid assistants", ModelMaker.LIQUID, CHAT, "lfm2"),
    spec("mistral", "Mistral", "Balanced open chat", ModelMaker.MISTRAL, CHAT, "mistral"),
    spec("smollm", "SmolLM", "Tiny, quick assistants", ModelMaker.HUGGING_FACE, CHAT, "smollm"),

    // ── Vision ── the three Cosmos3-Edge bundles (understanding + generation) read as one
    // family; the OCR/parse pair is separate from the general Nemotron vision model.
    spec("cosmos3-edge-vision", "Cosmos3-Edge", "Omnimodal image understanding", ModelMaker.NVIDIA, VISION, "cosmos3"),
    spec("nemotron-ocr", "Nemotron OCR", "Document OCR and parsing", ModelMaker.NVIDIA, VISION, "nemotron_ocr", "nemotron_parse"),
    spec("nemotron-vision", "Nemotron Vision", "NVIDIA image understanding", ModelMaker.NVIDIA, VISION, "nemotron"),
    spec("internvl", "InternVL", "Detailed image descriptions", ModelMaker.OPEN_SOURCE, VISION, "internvl"),
    spec("qwen3-vl", "Qwen3-VL", "Chat about photos", ModelMaker.ALIBABA, VISION, "qwen3_vl", "qwen3-vl"),
    spec("qwen2-vl", "Qwen2-VL", "Reliable photo chat", ModelMaker.ALIBABA, VISION, "qwen2-vl", "qwen2.5-vl"),
    spec("lfm2-vl", "LFM2 Vision", "Compact models that can see", ModelMaker.LIQUID, VISION, "lfm2"),
    spec("smolvlm", "SmolVLM", "Tiny models that can see", ModelMaker.HUGGING_FACE, VISION, "smolvlm"),
    spec("gemma-vl", "Gemma Vision", "Google's image models", ModelMaker.GOOGLE, VISION, "gemma"),
    spec("lama", "LaMa", "Erases objects from photos", ModelMaker.OPEN_SOURCE, VISION, "lama_dilated"),

    // ── Voice ── "canary" precedes "nemotron" so Canary keeps its own card.
    spec("whisper", "Whisper", "Speech-to-text", ModelMaker.OPENAI, VOICE, "whisper"),
    spec("moonshine", "Moonshine", "Fast speech-to-text", ModelMaker.OPEN_SOURCE, VOICE, "moonshine"),
    spec("parakeet", "Parakeet", "NVIDIA speech-to-text", ModelMaker.NVIDIA, VOICE, "parakeet"),
    spec("canary", "Canary", "Multilingual speech-to-text", ModelMaker.NVIDIA, VOICE, "canary"),
    spec("nemotron-asr", "Nemotron ASR", "Streaming speech-to-text", ModelMaker.NVIDIA, VOICE, "nemotron"),
    spec("melotts", "MeloTTS", "Natural read-aloud", ModelMaker.OPEN_SOURCE, VOICE, "melo"),
    spec("kokoro", "Kokoro", "Expressive read-aloud", ModelMaker.OPEN_SOURCE, VOICE, "kokoro"),
    spec("kitten", "Kitten", "Tiny read-aloud voices", ModelMaker.OPEN_SOURCE, VOICE, "kitten"),
    spec("piper", "Piper", "Lightweight read-aloud", ModelMaker.OPEN_SOURCE, VOICE, "piper"),
    spec("silero", "Silero VAD", "Detects when you speak", ModelMaker.OPEN_SOURCE, VOICE, "silero"),

    // ── Embedding ── "rerank" precedes "nv_embed" (NV-RerankQA is not a retriever), and
    // "nemotron" precedes it too so every Nemotron embedder lands in one family.
    spec("nv-rerank", "NV-Rerank", "Reranks search results", ModelMaker.NVIDIA, EMBEDDING, "rerank"),
    spec("embeddinggemma", "EmbeddingGemma", "Document search", ModelMaker.GOOGLE, EMBEDDING, "embeddinggemma"),
    spec("siglip", "SigLIP2", "Image and text search", ModelMaker.GOOGLE, EMBEDDING, "siglip"),
    spec("nemotron-embed", "Nemotron Embed", "NVIDIA document search", ModelMaker.NVIDIA, EMBEDDING, "nemotron"),
    spec("nv-embed", "NV-Embed", "Question-answer retrieval", ModelMaker.NVIDIA, EMBEDDING, "nv_embed", "nv-embed"),
    spec("minilm", "MiniLM", "Lightweight document search", ModelMaker.OPEN_SOURCE, EMBEDDING, "minilm"),
)

/**
 * Resolves a model to its family. Models the table does not name — user-imported Hugging
 * Face downloads, for instance — get a family of their own keyed by id, so unrelated
 * singletons never collapse into a shared "Other" card.
 */
fun RAModelInfo.family(): ModelFamily {
    val bucket = categoryBucket()
    if (isPlatformBuiltIn()) {
        return ModelFamily("built-in-$bucket", "Built-in", "Provided by your device", ModelMaker.APPLE)
    }
    val haystack = "$id $name".lowercase()
    familySpecs.firstOrNull { it.matches(haystack, bucket) }?.let { return it.toFamily() }
    return ModelFamily("model-$id", displayTitle(), bucket.fallbackTagline, ModelMaker.OPEN_SOURCE)
}

fun RAModelInfo.maker(): ModelMaker = family().maker

fun RAModelInfo.brand(): Brand = maker().brand

// Models supplied by the operating system rather than downloaded (iOS only today).
private fun RAModelInfo.isPlatformBuiltIn(): Boolean =
    framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
