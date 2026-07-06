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

    fun accepts(model: RAModelInfo): Boolean = when (this) {
        LLM, RAG_LLM -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)
        STT -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION)
        TTS -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS)
        VAD -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION)
        VLM -> model.isVisionLanguageModel
        RAG_EMBEDDING -> model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_EMBEDDING)
    }
}
