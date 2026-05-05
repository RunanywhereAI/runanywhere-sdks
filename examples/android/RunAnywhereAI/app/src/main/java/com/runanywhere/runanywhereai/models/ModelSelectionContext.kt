/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Example-app UI helper for context-aware model selection. This is NOT an SDK
 * type — it's a Kotlin-side filter helper over generated proto enums, used by
 * the Android example's ModelSelectionSheet / ModelRequiredOverlay flows.
 *
 * Moved out of the SDK's `commonMain/public/extensions/Models/ModelTypes.kt`
 * per kotlin.md KOT-15 — the only consumer was this example app, so it does
 * not belong in the public SDK surface.
 */

package com.runanywhere.runanywhereai.models

import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory

/**
 * Context for model selection UI. Not an IDL schema; purely a UI-layer filter
 * helper over the generated model category/framework enums.
 */
enum class ModelSelectionContext(
    val key: String,
) {
    LLM("llm"),
    STT("stt"),
    TTS("tts"),
    VOICE("voice"),
    RAG_EMBEDDING("ragEmbedding"),
    RAG_LLM("ragLLM"),
    VLM("vlm"),
    ;

    val title: String
        get() =
            when (this) {
                LLM -> "Select LLM Model"
                STT -> "Select STT Model"
                TTS -> "Select TTS Voice"
                VOICE -> "Select Voice Models"
                RAG_EMBEDDING -> "Select Embedding Model"
                RAG_LLM -> "Select LLM Model"
                VLM -> "Select Vision Model"
            }

    fun isCategoryRelevant(category: ModelCategory): Boolean =
        when (this) {
            LLM -> category == ModelCategory.MODEL_CATEGORY_LANGUAGE
            STT -> category == ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
            TTS -> category == ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
            VOICE ->
                category == ModelCategory.MODEL_CATEGORY_LANGUAGE ||
                    category == ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION ||
                    category == ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS ||
                    category == ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
            RAG_EMBEDDING -> category == ModelCategory.MODEL_CATEGORY_EMBEDDING
            RAG_LLM -> category == ModelCategory.MODEL_CATEGORY_LANGUAGE
            VLM ->
                category == ModelCategory.MODEL_CATEGORY_MULTIMODAL ||
                    category == ModelCategory.MODEL_CATEGORY_VISION
        }

    fun isFrameworkRelevant(framework: InferenceFramework): Boolean =
        when (this) {
            LLM ->
                framework == InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP ||
                    framework == InferenceFramework.INFERENCE_FRAMEWORK_GENIE ||
                    framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS
            STT -> framework == InferenceFramework.INFERENCE_FRAMEWORK_ONNX
            TTS ->
                framework == InferenceFramework.INFERENCE_FRAMEWORK_ONNX ||
                    framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS ||
                    framework == InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO
            VOICE -> LLM.isFrameworkRelevant(framework) || STT.isFrameworkRelevant(framework) || TTS.isFrameworkRelevant(framework)
            RAG_EMBEDDING -> framework == InferenceFramework.INFERENCE_FRAMEWORK_ONNX
            RAG_LLM -> framework == InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
            VLM -> framework == InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP
        }
}
