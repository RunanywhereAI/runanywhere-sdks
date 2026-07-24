package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import com.runanywhere.runanywhereai.ui.theme.icons.Brand
import com.runanywhere.runanywhereai.ui.theme.icons.RACBrands
import com.runanywhere.sdk.public.types.RAModelInfo

/**
 * Organisation (publisher) for a model. The picker groups by this alone — no
 * family/series cards. Declaration order is the picker's org ordering.
 */
enum class ModelOrg(val brand: Brand) {
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
 * Id/name tokens → org. First match wins, so specific publishers precede generic ones
 * ("nemotron" before "llama", "deepseek" before "qwen").
 */
private data class OrgSpec(val org: ModelOrg, val tokens: List<String>) {
    fun matches(haystack: String): Boolean = tokens.any { it in haystack }
}

private fun org(org: ModelOrg, vararg tokens: String) = OrgSpec(org, tokens.toList())

private val orgSpecs: List<OrgSpec> = listOf(
    // NVIDIA first among Llama-derived names so Nemotron / Canary / Parakeet stay NVIDIA.
    org(ModelOrg.NVIDIA, "nemotron", "nemoguard", "cosmos", "canary", "parakeet", "nv_embed", "nv-embed", "nv_rerank", "nvidia"),
    org(ModelOrg.DEEPSEEK, "deepseek"),
    org(ModelOrg.PRISM, "bonsai"),
    org(ModelOrg.MICROSOFT, "phi"),
    org(ModelOrg.GOOGLE, "gemma", "embeddinggemma", "siglip"),
    org(ModelOrg.META, "llama"),
    org(ModelOrg.ALIBABA, "qwen"),
    org(ModelOrg.LIQUID, "lfm2"),
    org(ModelOrg.MISTRAL, "mistral"),
    org(ModelOrg.HUGGING_FACE, "smollm", "smolvlm"),
    org(ModelOrg.OPENAI, "whisper"),
    org(ModelOrg.OPEN_SOURCE, "internvl", "lama_dilated", "moonshine", "melo", "kokoro", "kitten", "piper", "silero", "minilm"),
)

fun RAModelInfo.org(): ModelOrg {
    if (isPlatformBuiltIn()) return ModelOrg.APPLE
    val haystack = "$id $name".lowercase()
    return orgSpecs.firstOrNull { it.matches(haystack) }?.org ?: ModelOrg.OPEN_SOURCE
}

fun RAModelInfo.maker(): ModelOrg = org()

fun RAModelInfo.brand(): Brand = org().brand

private fun RAModelInfo.isPlatformBuiltIn(): Boolean =
    framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
        framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS
