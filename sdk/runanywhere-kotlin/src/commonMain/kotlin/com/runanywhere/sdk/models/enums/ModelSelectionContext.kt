package com.runanywhere.sdk.models.enums

import kotlinx.serialization.Serializable

/**
 * Context for filtering frameworks and models based on the current experience/modality
 * Matches iOS ModelSelectionContext enum exactly
 *
 * Reference: examples/ios/RunAnywhereAI/Features/Models/ModelSelectionSheet.swift
 */
@Serializable
enum class ModelSelectionContext(
    val title: String,
    val description: String
) {
    /**
     * Chat experience - show LLM frameworks (llama.cpp, Foundation Models, etc.)
     */
    LLM("Select LLM Model", "Text generation models for chat"),

    /**
     * Speech-to-Text - show STT frameworks (WhisperKit, ONNX STT, etc.)
     */
    STT("Select STT Model", "Speech recognition models"),

    /**
     * Text-to-Speech - show TTS frameworks (ONNX TTS/Piper, System TTS, etc.)
     */
    TTS("Select TTS Model", "Text-to-speech models"),

    /**
     * Voice Assistant - show all voice-related (LLM + STT + TTS)
     */
    VOICE("Select Model", "All voice-related models");

    /**
     * Model categories relevant to this context
     * Matches iOS relevantCategories property
     */
    val relevantCategories: Set<ModelCategory>
        get() = when (this) {
            LLM -> setOf(ModelCategory.LANGUAGE, ModelCategory.LANGUAGE_MODEL, ModelCategory.MULTIMODAL)
            STT -> setOf(ModelCategory.SPEECH_RECOGNITION)
            TTS -> setOf(ModelCategory.SPEECH_SYNTHESIS)
            VOICE -> setOf(
                ModelCategory.LANGUAGE,
                ModelCategory.LANGUAGE_MODEL,
                ModelCategory.MULTIMODAL,
                ModelCategory.SPEECH_RECOGNITION,
                ModelCategory.SPEECH_SYNTHESIS
            )
        }

    /**
     * Framework modalities relevant to this context
     */
    val relevantModalities: Set<FrameworkModality>
        get() = when (this) {
            LLM -> setOf(FrameworkModality.TEXT_TO_TEXT, FrameworkModality.MULTIMODAL)
            STT -> setOf(FrameworkModality.VOICE_TO_TEXT)
            TTS -> setOf(FrameworkModality.TEXT_TO_VOICE)
            VOICE -> setOf(
                FrameworkModality.TEXT_TO_TEXT,
                FrameworkModality.VOICE_TO_TEXT,
                FrameworkModality.TEXT_TO_VOICE,
                FrameworkModality.MULTIMODAL
            )
        }

    /**
     * Check if a framework is relevant for this context
     */
    fun isFrameworkRelevant(framework: InferenceFramework): Boolean {
        val frameworkModalities = framework.supportedModalities
        return frameworkModalities.any { relevantModalities.contains(it) }
    }

    /**
     * Check if a model category is relevant for this context
     */
    fun isCategoryRelevant(category: ModelCategory): Boolean {
        return relevantCategories.contains(category)
    }

    companion object {
        /**
         * Get context from a model category
         */
        fun from(category: ModelCategory): ModelSelectionContext {
            return when (category) {
                ModelCategory.LANGUAGE, ModelCategory.LANGUAGE_MODEL -> LLM
                ModelCategory.SPEECH_RECOGNITION, ModelCategory.AUDIO -> STT
                ModelCategory.SPEECH_SYNTHESIS -> TTS
                ModelCategory.MULTIMODAL, ModelCategory.VISION, ModelCategory.IMAGE_GENERATION -> LLM
            }
        }

        /**
         * Get context from a framework modality
         */
        fun from(modality: FrameworkModality): ModelSelectionContext {
            return when (modality) {
                FrameworkModality.TEXT_TO_TEXT -> LLM
                FrameworkModality.VOICE_TO_TEXT -> STT
                FrameworkModality.TEXT_TO_VOICE -> TTS
                FrameworkModality.IMAGE_TO_TEXT, FrameworkModality.TEXT_TO_IMAGE, FrameworkModality.MULTIMODAL -> LLM
            }
        }
    }
}
