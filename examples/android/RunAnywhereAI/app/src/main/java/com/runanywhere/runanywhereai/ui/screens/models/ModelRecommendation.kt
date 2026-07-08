package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.types.RAModelInfo

/**
 * Hardware-aware model recommendation engine.
 *
 * Pure, Compose-free logic: given the detected [HardwareTier] + NPU flag and the
 * full available model list, it produces a curated [RecommendedSelection] the picker
 * surfaces above the searchable catalog. Preferred IDs are chosen per tier (NPU vs
 * non-NPU); anything missing from the list is skipped and back-filled by category +
 * memory budget so the section is never empty on a device that has models.
 */
data class RecommendedSelection(
    val defaultModel: RAModelInfo?,
    val recommendedLLMs: List<RAModelInfo>,
    val asr: RAModelInfo?,
    val tts: RAModelInfo?,
    val vlm: RAModelInfo?,
    val embedding: RAModelInfo?,
) {
    // Every model surfaced by the engine, de-duplicated — used by the picker to
    // exclude these from the full-catalog section below.
    val allIds: Set<String>
        get() = buildSet {
            defaultModel?.let { add(it.id) }
            recommendedLLMs.forEach { add(it.id) }
            asr?.let { add(it.id) }
            tts?.let { add(it.id) }
            vlm?.let { add(it.id) }
            embedding?.let { add(it.id) }
        }
}

object ModelRecommendation {

    // Per-tier memory budget (bytes) — a model only qualifies if its footprint fits.
    // Kept generous for NPU devices since the accelerator offloads the heavy work.
    private fun memoryBudgetBytes(tier: HardwareTier): Long = when (tier) {
        HardwareTier.HIGH_END -> 7_000_000_000L
        HardwareTier.MID_RANGE -> 3_000_000_000L
        HardwareTier.LOW_END -> 1_200_000_000L
    }

    // Preferred LLM ids per tier, ordered best-first. GGUF (llama.cpp) picks that run
    // on any device without an NPU. Spread across fast / balanced / tool / thinking.
    private val ggufLLMsByTier: Map<HardwareTier, List<String>> = mapOf(
        HardwareTier.HIGH_END to listOf(
            "lfm2.5-1.2b-instruct-q4_k_m",
            "qwen3-1.7b-q4_k_m",
            "lfm2-1.2b-tool-q4_k_m",
            "qwen3-4b-q4_k_m",
            "qwen3-0.6b-q4_k_m",
        ),
        HardwareTier.MID_RANGE to listOf(
            "qwen3-0.6b-q4_k_m",
            "lfm2.5-1.2b-instruct-q4_k_m",
            "lfm2-1.2b-tool-q4_k_m",
            "qwen3-1.7b-q4_k_m",
            "qwen2.5-0.5b-instruct-q6_k",
        ),
        HardwareTier.LOW_END to listOf(
            "lfm2-350m-q4_k_m",
            "qwen3-0.6b-q4_k_m",
            "qwen2.5-0.5b-instruct-q6_k",
            "qwen3.5-0.8b-q4_k_m",
        ),
    )

    // HNPU (QHexRT) LLMs surfaced first on NPU high-end devices, ordered best-first.
    private val npuLLMs: List<String> = listOf(
        "qwen3_5_0_8b",
        "lfm2_5_350m",
        "qwen3_0_6b",
        "lfm2_5_230m",
    )

    // Preferred non-NPU picks per modality (GGUF / Sherpa / ONNX).
    private const val GGUF_ASR = "sherpa-onnx-whisper-tiny.en"
    private const val GGUF_TTS = "vits-piper-en_US-lessac-medium"
    private val ggufVLMByTier: Map<HardwareTier, List<String>> = mapOf(
        HardwareTier.HIGH_END to listOf("qwen2-vl-2b-instruct-q4_k_m", "smolvlm2-500m-video-instruct-q8_0"),
        HardwareTier.MID_RANGE to listOf("smolvlm2-500m-video-instruct-q8_0", "smolvlm2-256m-video-instruct-q8_0"),
        HardwareTier.LOW_END to listOf("smolvlm2-256m-video-instruct-q8_0"),
    )
    private const val ONNX_EMBEDDING = "all-minilm-l6-v2"
    private const val ONNX_VAD = "silero-vad"

    // Preferred HNPU picks per modality on NPU high-end devices.
    private const val NPU_ASR = "whisper_base"
    private const val NPU_TTS = "kokoro_en"
    private const val NPU_VLM = "qwen3_vl"
    private const val NPU_EMBEDDING = "embeddinggemma_300m"

    fun recommend(
        tier: HardwareTier,
        hasNpu: Boolean,
        models: List<RAModelInfo>,
    ): RecommendedSelection {
        val budget = memoryBudgetBytes(tier)
        val byId = models.associateBy { it.id }
        val preferNpu = hasNpu && tier == HardwareTier.HIGH_END

        val llms = pickLLMs(tier, preferNpu, budget, byId, models)
        val default = llms.firstOrNull()

        return RecommendedSelection(
            defaultModel = default,
            recommendedLLMs = llms,
            asr = pickAsr(preferNpu, hasNpu, budget, byId, models),
            tts = pickTts(preferNpu, hasNpu, budget, byId, models),
            vlm = pickVlm(tier, preferNpu, hasNpu, budget, byId, models),
            embedding = pickEmbedding(preferNpu, hasNpu, budget, byId, models),
        )
    }

    /**
     * A best-for-device Voice AI pipeline: speech-to-text, chat, text-to-speech, and
     * (optionally) a voice-activity model. Pure — reused by the Voice screen to
     * pre-select the whole trio with zero hand-picking. Any component may be null when
     * the catalog has nothing that fits; the caller decides how to degrade.
     */
    data class VoicePipeline(
        val stt: RAModelInfo?,
        val llm: RAModelInfo?,
        val tts: RAModelInfo?,
        val vad: RAModelInfo?,
    ) {
        val core: List<RAModelInfo> get() = listOfNotNull(stt, llm, tts)
        val all: List<RAModelInfo> get() = listOfNotNull(stt, llm, tts, vad)
        val isComplete: Boolean get() = stt != null && llm != null && tts != null
    }

    fun recommendVoicePipeline(
        tier: HardwareTier,
        hasNpu: Boolean,
        models: List<RAModelInfo>,
    ): VoicePipeline {
        val budget = memoryBudgetBytes(tier)
        val byId = models.associateBy { it.id }
        val preferNpu = hasNpu && tier == HardwareTier.HIGH_END
        return VoicePipeline(
            stt = pickAsr(preferNpu, hasNpu, budget, byId, models),
            llm = pickLLMs(tier, preferNpu, budget, byId, models).firstOrNull(),
            tts = pickTts(preferNpu, hasNpu, budget, byId, models),
            // VAD is tiny + backend-neutral (ONNX Silero); include it so the pipeline is
            // fully pre-staged. The voice agent also auto-ensures it, so it's a nicety.
            vad = pickCategory(
                preferredIds = listOf(ONNX_VAD),
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                budget = budget,
                byId = byId,
                models = models,
                allowNpu = hasNpu,
            ),
        )
    }

    // The single recommended model for a scoped modality picker. Lets each
    // single-modality picker highlight "Best for this device" consistently.
    fun recommendedFor(
        context: ModelSelectionContext,
        tier: HardwareTier,
        hasNpu: Boolean,
        models: List<RAModelInfo>,
    ): RAModelInfo? {
        val budget = memoryBudgetBytes(tier)
        val byId = models.associateBy { it.id }
        val preferNpu = hasNpu && tier == HardwareTier.HIGH_END
        return when (context) {
            ModelSelectionContext.LLM,
            ModelSelectionContext.RAG_LLM -> pickLLMs(tier, preferNpu, budget, byId, models).firstOrNull()
            ModelSelectionContext.STT -> pickAsr(preferNpu, hasNpu, budget, byId, models)
            ModelSelectionContext.TTS -> pickTts(preferNpu, hasNpu, budget, byId, models)
            ModelSelectionContext.VLM -> pickVlm(tier, preferNpu, hasNpu, budget, byId, models)
            ModelSelectionContext.RAG_EMBEDDING -> pickEmbedding(preferNpu, hasNpu, budget, byId, models)
            ModelSelectionContext.VAD -> pickCategory(
                preferredIds = listOf(ONNX_VAD),
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                budget = budget,
                byId = byId,
                models = models,
                allowNpu = hasNpu,
            )
        }
    }

    private fun pickAsr(
        preferNpu: Boolean,
        hasNpu: Boolean,
        budget: Long,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): RAModelInfo? = pickCategory(
        preferredIds = if (preferNpu) listOf(NPU_ASR, GGUF_ASR) else listOf(GGUF_ASR),
        category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        budget = budget,
        byId = byId,
        models = models,
        allowNpu = hasNpu,
    )

    private fun pickTts(
        preferNpu: Boolean,
        hasNpu: Boolean,
        budget: Long,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): RAModelInfo? = pickCategory(
        preferredIds = if (preferNpu) listOf(NPU_TTS, GGUF_TTS) else listOf(GGUF_TTS),
        category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        budget = budget,
        byId = byId,
        models = models,
        allowNpu = hasNpu,
    )

    private fun pickVlm(
        tier: HardwareTier,
        preferNpu: Boolean,
        hasNpu: Boolean,
        budget: Long,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): RAModelInfo? = pickCategory(
        preferredIds = buildList {
            if (preferNpu) add(NPU_VLM)
            addAll(ggufVLMByTier[tier].orEmpty())
        },
        category = ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        secondaryCategory = ModelCategory.MODEL_CATEGORY_VISION,
        budget = budget,
        byId = byId,
        models = models,
        allowNpu = hasNpu,
    )

    private fun pickEmbedding(
        preferNpu: Boolean,
        hasNpu: Boolean,
        budget: Long,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): RAModelInfo? = pickCategory(
        preferredIds = if (preferNpu) listOf(NPU_EMBEDDING, ONNX_EMBEDDING) else listOf(ONNX_EMBEDDING),
        category = ModelCategory.MODEL_CATEGORY_EMBEDDING,
        budget = budget,
        byId = byId,
        models = models,
        allowNpu = hasNpu,
    )

    // Builds the 3–5 LLM shortlist: preferred ids first (HNPU first on NPU devices),
    // then a budget-fitting back-fill so the list is never empty on a stocked device.
    private fun pickLLMs(
        tier: HardwareTier,
        preferNpu: Boolean,
        budget: Long,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): List<RAModelInfo> {
        val ordered = buildList {
            if (preferNpu) addAll(npuLLMs)
            addAll(ggufLLMsByTier[tier].orEmpty())
        }
        val picked = LinkedHashMap<String, RAModelInfo>()
        ordered.forEach { id ->
            val model = byId[id] ?: return@forEach
            if (model.fits(budget)) picked[id] = model
        }
        if (picked.size < 3) {
            models.asSequence()
                .filter { it.category == ModelCategory.MODEL_CATEGORY_LANGUAGE }
                .filter { it.allowedForNpu(preferNpu) }
                .filter { it.fits(budget) }
                .sortedBy { it.effectiveBytes() }
                .forEach { if (picked.size < 5) picked.putIfAbsent(it.id, it) }
        }
        return picked.values.take(5)
    }

    // Resolves one recommended model for a modality: try preferred ids in order,
    // else fall back to any budget-fitting model in the category (NPU-gated).
    private fun pickCategory(
        preferredIds: List<String>,
        category: ModelCategory,
        secondaryCategory: ModelCategory? = null,
        budget: Long,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
        allowNpu: Boolean,
    ): RAModelInfo? {
        preferredIds.forEach { id ->
            val model = byId[id]
            if (model != null && model.allowedForNpu(allowNpu) && model.fits(budget)) return model
        }
        return models.asSequence()
            .filter { it.category == category || (secondaryCategory != null && it.category == secondaryCategory) }
            .filter { it.allowedForNpu(allowNpu) }
            .filter { it.fits(budget) }
            .minByOrNull { it.effectiveBytes() }
    }

    private fun RAModelInfo.fits(budget: Long): Boolean {
        val bytes = effectiveBytes()
        // Unknown sizes (0) are allowed through — the download flow surfaces the real cost.
        return bytes <= 0L || bytes <= budget
    }

    // NPU models are only ever recommended on devices that report a Hexagon NPU.
    private fun RAModelInfo.allowedForNpu(allowNpu: Boolean): Boolean =
        allowNpu || framework != InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT
}
