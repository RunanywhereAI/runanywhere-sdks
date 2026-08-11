package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.types.RAModelInfo

/**
 * Catalog preference order for the model picker.
 *
 * Device capability tier is not invented here — [HardwareTier.UNKNOWN] is the only
 * value [DeviceInfo] can surface until commons publishes a typed tier. Ranking uses
 * curated preferred IDs plus the typed NPU flag from [QHexRT.probeNpu], not RAM
 * thresholds or NPU-tier promotion.
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

    // Curated GGUF LLM ids, ordered best-first (product preference, not device fit).
    private val preferredGgufLLMs: List<String> = listOf(
        "lfm2.5-1.2b-instruct-q4_k_m",
        "qwen3-1.7b-q4_k_m",
        "lfm2-1.2b-tool-q4_k_m",
        "qwen3-0.6b-q4_k_m",
        "qwen2.5-0.5b-instruct-q6_k",
        "lfm2-350m-q4_k_m",
        "qwen3.5-0.8b-q4_k_m",
    )

    // HNPU (QHexRT) LLMs surfaced first when the device reports a Hexagon NPU.
    private val npuLLMs: List<String> = listOf(
        "qwen3_5_0_8b",
        "lfm2_5_350m",
        "qwen3_0_6b",
        "lfm2_5_230m",
    )

    private const val GGUF_ASR = "sherpa-onnx-whisper-tiny.en"
    private const val GGUF_TTS = "vits-piper-en_US-lessac-medium"
    private val preferredGgufVLMs: List<String> = listOf(
        "qwen2-vl-2b-instruct-q4_k_m",
        "smolvlm2-500m-video-instruct-q8_0",
        "smolvlm2-256m-video-instruct-q8_0",
    )
    private const val ONNX_EMBEDDING = "all-minilm-l6-v2"
    private const val ONNX_VAD = "silero-vad"

    private const val NPU_ASR = "whisper_base"
    private const val NPU_TTS = "kokoro_en"
    // InternVL is validated on V75/V79/V81. qwen3_vl has no V81 bundle and is
    // therefore absent from a correctly native-filtered V81 picker.
    private const val NPU_VLM = "internvl3_5_1b"
    private const val NPU_EMBEDDING = "embeddinggemma_300m"

    fun recommend(
        @Suppress("UNUSED_PARAMETER") tier: HardwareTier,
        hasNpu: Boolean,
        models: List<RAModelInfo>,
    ): RecommendedSelection {
        val byId = models.associateBy { it.id }
        val preferNpu = hasNpu

        val llms = pickLLMs(preferNpu, byId, models)
        val default = llms.firstOrNull()

        return RecommendedSelection(
            defaultModel = default,
            recommendedLLMs = llms,
            asr = pickAsr(preferNpu, hasNpu, byId, models),
            tts = pickTts(preferNpu, hasNpu, byId, models),
            vlm = pickVlm(preferNpu, hasNpu, byId, models),
            embedding = pickEmbedding(preferNpu, hasNpu, byId, models),
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
        @Suppress("UNUSED_PARAMETER") tier: HardwareTier,
        hasNpu: Boolean,
        models: List<RAModelInfo>,
    ): VoicePipeline {
        val byId = models.associateBy { it.id }
        val preferNpu = hasNpu
        return VoicePipeline(
            stt = pickAsr(preferNpu, hasNpu, byId, models),
            llm = pickLLMs(preferNpu, byId, models).firstOrNull(),
            tts = pickTts(preferNpu, hasNpu, byId, models),
            vad = pickCategory(
                preferredIds = listOf(ONNX_VAD),
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
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
        @Suppress("UNUSED_PARAMETER") tier: HardwareTier,
        hasNpu: Boolean,
        models: List<RAModelInfo>,
    ): RAModelInfo? {
        val byId = models.associateBy { it.id }
        val preferNpu = hasNpu
        return when (context) {
            ModelSelectionContext.LLM,
            ModelSelectionContext.RAG_LLM -> pickLLMs(preferNpu, byId, models).firstOrNull()
            ModelSelectionContext.STT -> pickAsr(preferNpu, hasNpu, byId, models)
            ModelSelectionContext.TTS -> pickTts(preferNpu, hasNpu, byId, models)
            ModelSelectionContext.VLM -> pickVlm(preferNpu, hasNpu, byId, models)
            ModelSelectionContext.RAG_EMBEDDING -> pickEmbedding(preferNpu, hasNpu, byId, models)
            ModelSelectionContext.VAD -> pickCategory(
                preferredIds = listOf(ONNX_VAD),
                category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
                byId = byId,
                models = models,
                allowNpu = hasNpu,
            )
            ModelSelectionContext.SEGMENTATION -> pickCategory(
                preferredIds = listOf("segformer-b0-ade20k"),
                category = ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
                byId = byId,
                models = models,
                allowNpu = hasNpu,
            )
            ModelSelectionContext.IMAGE_GENERATION ->
                models.filter { it.servesTextToImage() && it.allowedForNpu(hasNpu) }
                    .minByOrNull { it.effectiveBytes() }
                    ?: models.firstOrNull { it.servesTextToImage() && it.allowedForNpu(hasNpu) }
            ModelSelectionContext.OCR ->
                models.filter { it.isDocumentOcrModel() && it.allowedForNpu(hasNpu) }
                    .sortedBy { it.effectiveBytes() }
                    .let { ocr ->
                        ocr.firstOrNull { it.id == "nemotron_ocr_v1" || it.id == "nemotron_ocr" }
                            ?: ocr.firstOrNull()
                    }
        }
    }

    private fun pickAsr(
        preferNpu: Boolean,
        hasNpu: Boolean,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): RAModelInfo? = pickCategory(
        preferredIds = if (preferNpu) listOf(NPU_ASR, GGUF_ASR) else listOf(GGUF_ASR),
        category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        byId = byId,
        models = models,
        allowNpu = hasNpu,
    )

    private fun pickTts(
        preferNpu: Boolean,
        hasNpu: Boolean,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): RAModelInfo? = pickCategory(
        preferredIds = if (preferNpu) listOf(NPU_TTS, GGUF_TTS) else listOf(GGUF_TTS),
        category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        byId = byId,
        models = models,
        allowNpu = hasNpu,
    )

    private fun pickVlm(
        preferNpu: Boolean,
        hasNpu: Boolean,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): RAModelInfo? = pickCategory(
        preferredIds = buildList {
            if (preferNpu) add(NPU_VLM)
            addAll(preferredGgufVLMs)
        },
        category = ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        secondaryCategory = ModelCategory.MODEL_CATEGORY_VISION,
        byId = byId,
        models = models,
        allowNpu = hasNpu,
    )

    private fun pickEmbedding(
        preferNpu: Boolean,
        hasNpu: Boolean,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): RAModelInfo? = pickCategory(
        preferredIds = if (preferNpu) listOf(NPU_EMBEDDING, ONNX_EMBEDDING) else listOf(ONNX_EMBEDDING),
        category = ModelCategory.MODEL_CATEGORY_EMBEDDING,
        byId = byId,
        models = models,
        allowNpu = hasNpu,
    )

    // Preferred ids first (HNPU first when NPU is present), then category back-fill.
    private fun pickLLMs(
        preferNpu: Boolean,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
    ): List<RAModelInfo> {
        val ordered = buildList {
            if (preferNpu) addAll(npuLLMs)
            addAll(preferredGgufLLMs)
        }
        val picked = LinkedHashMap<String, RAModelInfo>()
        ordered.forEach { id ->
            val model = byId[id] ?: return@forEach
            if (model.allowedForNpu(preferNpu)) picked[id] = model
        }
        if (picked.size < 3) {
            models.asSequence()
                .filter { it.category == ModelCategory.MODEL_CATEGORY_LANGUAGE }
                .filter { it.allowedForNpu(preferNpu) }
                .sortedBy { it.effectiveBytes() }
                .forEach { if (picked.size < 5) picked.putIfAbsent(it.id, it) }
        }
        return picked.values.take(5)
    }

    private fun pickCategory(
        preferredIds: List<String>,
        category: ModelCategory,
        secondaryCategory: ModelCategory? = null,
        byId: Map<String, RAModelInfo>,
        models: List<RAModelInfo>,
        allowNpu: Boolean,
    ): RAModelInfo? {
        preferredIds.forEach { id ->
            val model = byId[id]
            if (model != null && model.allowedForNpu(allowNpu)) return model
        }
        return models.asSequence()
            .filter { it.category == category || (secondaryCategory != null && it.category == secondaryCategory) }
            .filter { it.allowedForNpu(allowNpu) }
            .minByOrNull { it.effectiveBytes() }
    }

    // NPU models are only ever recommended on devices that report a Hexagon NPU.
    private fun RAModelInfo.allowedForNpu(allowNpu: Boolean): Boolean =
        allowNpu || framework != InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT
}
