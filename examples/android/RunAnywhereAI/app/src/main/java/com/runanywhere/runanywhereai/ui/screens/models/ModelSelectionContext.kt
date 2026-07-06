package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.public.types.RAModelInfo

// Which model category a selection sheet is for. UI-layer filter over proto categories.
enum class ModelSelectionContext(val title: String) {
    LLM("Choose Chat Model"),
    STT("Choose Listening Model"),
    TTS("Choose Voice"),
    VAD("Choose Turn-taking Model"),
    VLM("Choose Image Model"),
    RAG_EMBEDDING("Choose Document Index Model"),
    RAG_LLM("Choose Document Answer Model"),
    ;

    fun accepts(category: ModelCategory): Boolean = when (this) {
        LLM, RAG_LLM -> category == ModelCategory.MODEL_CATEGORY_LANGUAGE
        STT -> category == ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
        TTS -> category == ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        VAD -> category == ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        VLM -> category == ModelCategory.MODEL_CATEGORY_MULTIMODAL ||
            category == ModelCategory.MODEL_CATEGORY_VISION
        RAG_EMBEDDING -> category == ModelCategory.MODEL_CATEGORY_EMBEDDING
    }

    // Category to query/load under. null = mixed or selected by reference.
    // RAG models are picked by reference; the RAG pipeline loads them by id when it's created.
    val loadCategory: ModelCategory? get() = when (this) {
        LLM -> ModelCategory.MODEL_CATEGORY_LANGUAGE
        STT -> ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
        TTS -> ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        VAD -> ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        VLM -> ModelCategory.MODEL_CATEGORY_MULTIMODAL
        RAG_EMBEDDING, RAG_LLM -> null
    }

    fun loadCategoryFor(model: RAModelInfo): ModelCategory? = when (this) {
        VLM -> when (model.category) {
            ModelCategory.MODEL_CATEGORY_VISION,
            ModelCategory.MODEL_CATEGORY_MULTIMODAL,
            -> model.category
            else -> loadCategory
        }
        else -> loadCategory
    }
}
