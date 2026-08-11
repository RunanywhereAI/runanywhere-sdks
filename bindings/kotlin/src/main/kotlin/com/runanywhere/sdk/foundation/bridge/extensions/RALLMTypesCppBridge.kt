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

import ai.runanywhere.proto.v1.ChatMessage
import ai.runanywhere.proto.v1.ExecutionTarget
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.MessageRole
import ai.runanywhere.proto.v1.ThinkingTagPattern
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.public.types.RAExecutionTarget
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RAThinkingTagPattern

// MARK: - RALLMGenerationOptions: C-bridge + convenience

/**
 * Build a `RALLMGenerateRequest` from these options + a prompt.
 *
 * `LLMGenerateRequest.prompt`/`.history` were deleted outright
 * (idl/llm_service.proto): the request now carries only `messages` (oldest
 * first, ending with the turn the model must answer). Generation controls
 * remain in the canonical `options` envelope.
 */
fun RALLMGenerationOptions.toRALLMGenerateRequest(prompt: String): RALLMGenerateRequest {
    val defaults = RALLMGenerationOptions.defaults()
    val requestOptions =
        copy(
            max_output_tokens = max_output_tokens?.takeIf { it > 0 } ?: defaults.max_output_tokens,
            // max_output_tokens/temperature/top_p/repeat_penalty are all
            // optional now (idl/llm_options.proto): absent means "let the
            // engine decide," so zero is a real caller-supplied greedy
            // temperature that survives, and only an explicit null falls
            // back to defaults().
            temperature = temperature?.coerceIn(0.0f, 2.0f) ?: defaults.temperature,
            top_p = top_p?.takeIf { it > 0.0f } ?: defaults.top_p,
            repeat_penalty = repeat_penalty?.takeIf { it > 0.0f } ?: defaults.repeat_penalty,
        )
    return RALLMGenerateRequest(
        options = requestOptions,
        messages = listOf(ChatMessage(role = MessageRole.MESSAGE_ROLE_USER, content = prompt)),
    )
}

// MARK: - RALLMGenerationResult: proto-convenience accessors

/**
 * Alias for `output_tokens` matching Swift `RALLMGenerationResult.tokensUsed`.
 */
val RALLMGenerationResult.tokensUsed: Int
    get() = usage?.output_tokens ?: 0

/**
 * Alias for `generation_time_ms` matching Swift `RALLMGenerationResult.latencyMs`.
 */
val RALLMGenerationResult.latencyMs: Double
    get() = generation_time_ms

/**
 * Optional time-to-first-token (Swift `RALLMGenerationResult.timeToFirstTokenMs`).
 * `LLMGenerationResult.ttft_ms` was deleted outright -- `TokenUsage.ttft_ms`
 * (`usage.ttft_ms`) is the canonical spelling for every result type now.
 */
val RALLMGenerationResult.timeToFirstTokenMs: Double?
    get() = usage?.ttft_ms?.toDouble()

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
 * (e.g. "llamacpp", "onnx", "qhexrt"). Used by non-proto bridge surfaces.
 * The Swift SDK gets this from `rac_wire_string` codegen; Kotlin maintains the
 * same table here.
 */
val InferenceFramework.wireString: String
    get() =
        when (this) {
            InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP -> "llamacpp"
            InferenceFramework.INFERENCE_FRAMEWORK_ONNX -> "onnx"
            InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS -> "foundation-models"
            InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS -> "system-tts"
            InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO -> "fluid-audio"
            InferenceFramework.INFERENCE_FRAMEWORK_COREML -> "coreml"
            InferenceFramework.INFERENCE_FRAMEWORK_MLX -> "mlx"
            InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT -> "qhexrt"
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
            InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED -> ""
        }
