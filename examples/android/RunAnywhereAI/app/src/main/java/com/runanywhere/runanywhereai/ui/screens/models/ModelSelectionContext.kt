package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.extensions.isVisionLanguageModel
import com.runanywhere.sdk.public.extensions.matchesLifecycleCategory
import com.runanywhere.sdk.public.types.RAModelInfo

// Which model category a selection sheet is for. UI-layer filter over proto categories.
enum class ModelSelectionContext(
    val title: String,
) {
    LLM("Choose Chat Model"),
    STT("Choose Listening Model"),
    TTS("Choose Voice"),
    VAD("Choose Turn-taking Model"),
    VLM("Choose Image Model"),
    RAG_EMBEDDING("Choose Document Index Model"),
    RAG_LLM("Choose Document Answer Model"),
    ;

    val loadsModel: Boolean get() = this != RAG_EMBEDDING && this != RAG_LLM

    /**
     * Native lifecycle categories that represent this runtime modality.
     *
     * Keep this mapping in one place: both the picker and every inference
     * preflight use it to query the C++ lifecycle, which is the source of
     * truth for the model that will actually execute. RAG models are selected
     * by reference when a pipeline is created, so they deliberately have no
     * lifecycle category here.
     */
    val lifecycleCategories: List<ModelCategory>
        get() = when (this) {
            LLM -> listOf(ModelCategory.MODEL_CATEGORY_LANGUAGE)
            STT -> listOf(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION)
            TTS -> listOf(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)
            VAD -> listOf(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION)
            VLM -> listOf(
                ModelCategory.MODEL_CATEGORY_MULTIMODAL,
                ModelCategory.MODEL_CATEGORY_VISION,
            )
            RAG_EMBEDDING, RAG_LLM -> emptyList()
        }

    fun accepts(model: RAModelInfo): Boolean = when (this) {
        LLM, RAG_LLM -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)
        STT -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION)
        TTS -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)
        VAD -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION)
        VLM -> model.isVisionLanguageModel
        // Text-passage retrievers only. Exclude cross-modal CLIP towers (SigLIP2's text tower is a
        // short-caption image-alignment encoder, not a document retriever), rerankers, and code
        // embedders — all register as MODEL_CATEGORY_EMBEDDING but silently return poor RAG retrieval.
        // Keeps genuine QA retrievers (nv_embedqa, embeddinggemma, all-minilm).
        RAG_EMBEDDING -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_EMBEDDING) &&
            !model.isVisionLanguageModel &&
            listOf("rerank", "siglip", "clip", "embedcode").none { model.id.contains(it, ignoreCase = true) }
    }
}
