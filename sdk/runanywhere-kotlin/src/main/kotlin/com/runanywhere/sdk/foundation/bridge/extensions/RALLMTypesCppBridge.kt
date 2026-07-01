/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * RALLMTypesCppBridge.kt
 *
 * C-bridge extensions on proto-generated RA* LLM types.
 *
 * Mirrors Swift `Foundation/Bridge/Extensions/RALLMTypes+CppBridge.swift`.
 * Pure conversion / ergonomic helpers; no JNI. All inference goes through
 * the proto-byte ABI — these extensions exist to wrap the canonical Wire
 * messages with Swift-style affordances (defaults, derived getters,
 * `toRALLMGenerateRequest`, `wireString`).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ExecutionTarget
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.StructuredOutputMode
import ai.runanywhere.proto.v1.ThinkingTagPattern
import com.runanywhere.sdk.public.types.RAExecutionTarget
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RAThinkingTagPattern

// MARK: - RALLMGenerationOptions: C-bridge + convenience

/**
 * Default LLM generation options matching Swift `RALLMGenerationOptions.defaults()`:
 * maxTokens=100, temperature=0.8, topP=1.0, topK=0, repetitionPenalty=1.0.
 */
fun LLMGenerationOptions.Companion.defaults(): RALLMGenerationOptions =
    RALLMGenerationOptions(
        max_tokens = 100,
        temperature = 0.8f,
        top_p = 1.0f,
        top_k = 0,
        repetition_penalty = 1.0f,
    )

/**
 * Build a `RALLMGenerateRequest` from these options + a prompt.
 *
 * Mirrors Swift `RALLMGenerationOptions.toRALLMGenerateRequest(prompt:)`:
 * - Copies all sampling fields (max_tokens, temperature, top_p, top_k,
 *   repetition_penalty, stop_sequences, streaming_enabled,
 *   preferred_framework, system_prompt).
 * - When `structured_output` is set, prefers its embedded schema +
 *   response_format + grammar over the bare `json_schema` field.
 * - Promotes `execution_target` and `preferred_framework` to their wire
 *   string forms.
 */
fun RALLMGenerationOptions.toRALLMGenerateRequest(
    prompt: String,
    chatHistory: List<String> = emptyList(),
): RALLMGenerateRequest {
    val so = structured_output
    val schema =
        when {
            so != null -> so.json_schema.orEmpty()
            else -> json_schema.orEmpty()
        }
    val responseFormat =
        when (so?.mode) {
            StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_OBJECT -> "json_object"
            StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA -> "json_schema"
            else -> ""
        }
    val grammar = so?.grammar.orEmpty()
    return RALLMGenerateRequest(
        prompt = prompt,
        max_tokens = max_tokens,
        temperature = temperature,
        top_p = top_p,
        top_k = top_k,
        repetition_penalty = repetition_penalty,
        stop_sequences = stop_sequences,
        streaming_enabled = streaming_enabled,
        preferred_framework = preferred_framework.wireString,
        system_prompt = system_prompt.orEmpty(),
        json_schema = schema,
        response_format = responseFormat,
        grammar = grammar,
        execution_target = execution_target?.wireString.orEmpty(),
        // idl-005: commons reads advanced knobs (disable_thinking, etc.) from nested options.
        options = this,
        chat_history = chatHistory,
    )
}

// MARK: - RALLMGenerationResult: proto-convenience accessors

/**
 * Alias for `tokens_generated` matching Swift `RALLMGenerationResult.tokensUsed`.
 */
val RALLMGenerationResult.tokensUsed: Int
    get() = tokens_generated

/**
 * Alias for `generation_time_ms` matching Swift `RALLMGenerationResult.latencyMs`.
 */
val RALLMGenerationResult.latencyMs: Double
    get() = generation_time_ms

/**
 * Optional time-to-first-token (Swift `RALLMGenerationResult.timeToFirstTokenMs`).
 * Returns null when the underlying Wire field is unset.
 */
val RALLMGenerationResult.timeToFirstTokenMs: Double?
    get() = ttft_ms

// MARK: - RAThinkingTagPattern: defaults

/**
 * Default thinking-tag pattern (`<think>`/`</think>`).
 * Mirrors Swift `RAThinkingTagPattern.defaultPattern`.
 */
val ThinkingTagPattern.Companion.defaultPattern: RAThinkingTagPattern
    get() = RAThinkingTagPattern(open_tag = "<think>", close_tag = "</think>")

// MARK: - RAExecutionTarget: wire string

/**
 * Canonical wire string for routing hints. Mirrors Swift
 * `RAExecutionTarget.wireString` ("on-device" / "cloud" / "auto" / "").
 */
val RAExecutionTarget.wireString: String
    get() =
        when (this) {
            ExecutionTarget.EXECUTION_TARGET_ON_DEVICE -> "on-device"
            ExecutionTarget.EXECUTION_TARGET_CLOUD -> "cloud"
            ExecutionTarget.EXECUTION_TARGET_AUTO -> "auto"
            ExecutionTarget.EXECUTION_TARGET_UNSPECIFIED -> ""
        }

// MARK: - RAInferenceFramework: wire string

/**
 * Canonical wire string for an inference framework — the lowercase short name
 * (e.g. "llamacpp", "onnx", "metalrt"). Used when serializing to the canonical
 * `RALLMGenerateRequest.preferred_framework` field. The Swift SDK gets this
 * for free from the `rac_wire_string` codegen in `RAConvenience.swift`; Kotlin
 * has no equivalent codegen so we maintain the table by hand.
 */
val InferenceFramework.wireString: String
    get() =
        when (this) {
            InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "llamacpp"
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "onnx"
            InferenceFramework.INFERENCE_FRAMEWORK_METALRT -> "metalrt"
            InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "foundation-models"
            InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> "system-tts"
            InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> "fluid-audio"
            InferenceFramework.INFERENCE_FRAMEWORK_COREML -> "coreml"
            InferenceFramework.INFERENCE_FRAMEWORK_MLX -> "mlx"
            InferenceFramework.INFERENCE_FRAMEWORK_GENIE -> "genie"
            InferenceFramework.INFERENCE_FRAMEWORK_TFLITE -> "tflite"
            InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH -> "executorch"
            InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE -> "mediapipe"
            InferenceFramework.INFERENCE_FRAMEWORK_MLC -> "mlc"
            InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM -> "pico-llm"
            InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS -> "piper-tts"
            InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS -> "swift-transformers"
            InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN -> "built-in"
            InferenceFramework.INFERENCE_FRAMEWORK_NONE -> "none"
            InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN -> "unknown"
            InferenceFramework.INFERENCE_FRAMEWORK_SHERPA -> "sherpa"
            InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> "qhexrt"
            InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED -> ""
        }
