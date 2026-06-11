package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.ModelCategory

// Which model category a selection sheet is for. UI-layer filter over proto categories.
enum class ModelSelectionContext(val title: String) {
    LLM("Select LLM Model"),
    STT("Select STT Model"),
    TTS("Select TTS Voice"),

    // Voice-agent TTS picker. Same category as TTS but excludes built-ins:
    // the voice agent needs a lifecycle-loaded TTS and the commons System TTS
    // plugin is Apple-only, so on Android a built-in selection passes the
    // screen's ready gate and then fails init with "Models not loaded: TTS".
    VOICE_TTS("Select TTS Voice"),
    VLM("Select Vision Model"),
    RAG_EMBEDDING("Select Embedding Model"),
    RAG_LLM("Select LLM Model"),
    ;

    fun accepts(category: ModelCategory): Boolean = when (this) {
        LLM, RAG_LLM -> category == ModelCategory.MODEL_CATEGORY_LANGUAGE
        STT -> category == ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
        TTS, VOICE_TTS -> category == ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        VLM -> category == ModelCategory.MODEL_CATEGORY_MULTIMODAL ||
            category == ModelCategory.MODEL_CATEGORY_VISION
        RAG_EMBEDDING -> category == ModelCategory.MODEL_CATEGORY_EMBEDDING
    }

    // Category to query/load under. null = mixed or selected by reference.
    // RAG models are picked by reference; the RAG pipeline loads them by id when it's created.
    val loadCategory: ModelCategory? get() = when (this) {
        LLM -> ModelCategory.MODEL_CATEGORY_LANGUAGE
        STT -> ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
        TTS, VOICE_TTS -> ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
        VLM -> ModelCategory.MODEL_CATEGORY_MULTIMODAL
        RAG_EMBEDDING, RAG_LLM -> null
    }

    // Whether built-in entries (System TTS, Foundation Models) are selectable.
    // Built-ins are picked by reference (no lifecycle load), which the voice
    // agent cannot consume.
    val allowsBuiltIn: Boolean get() = this != VOICE_TTS
}
