/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for text generation (LLM) operations.
 * Calls C++ directly via CppBridge.LLM for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+TextGeneration.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.FinishReason
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.LLMStreamEventKind
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.analyticsKey
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RALLMStreamEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.buffer
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.util.concurrent.atomic.AtomicBoolean

// MARK: - Text Generation

// MARK: - Generation Control

private val llmLogger = SDKLogger.llm

@Deprecated("Use RunAnywhere.llm.generate(prompt, options).")
suspend fun RunAnywhere.generate(
    prompt: String,
    options: RALLMGenerationOptions? = null,
): RALLMGenerationResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: RALLMGenerationOptions.defaults()
    llmLogger.info("[PARAMS] generate: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_output_tokens}")
    return CppBridgeLLM.generate(prompt, options)
}

@Deprecated("Use RunAnywhere.llm.generate(prompt, options).")
suspend fun RunAnywhere.generate(request: RALLMGenerateRequest): RALLMGenerationResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val requestOptions = request.options
    val systemPrompt = requestOptions?.system_prompt
    val systemPromptDesc =
        if (systemPrompt.isNullOrBlank()) {
            "nil"
        } else {
            "set(${systemPrompt.length} chars)"
        }
    llmLogger.info(
        "[PARAMS] generate: temperature=${requestOptions?.temperature ?: "default"}, " +
            "topP=${requestOptions?.top_p ?: "default"}, " +
            "maxTokens=${requestOptions?.max_output_tokens ?: "default"}, systemPrompt=$systemPromptDesc",
    )
    return CppBridgeLLM.generate(request)
}

@Deprecated("Use RunAnywhere.llm.generateStream(prompt, options).")
fun RunAnywhere.generateStream(
    prompt: String,
    options: RALLMGenerationOptions? = null,
): Flow<RALLMStreamEvent> {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val opts = options ?: RALLMGenerationOptions.defaults()
    llmLogger.info("[PARAMS] generateStream: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_output_tokens}")

    return losslessLLMStreamFlow(
        prepare = { ensureServicesReady() },
        generate = { onEvent -> CppBridgeLLM.generateStream(prompt, options, onEvent) },
        cancel = { CppBridgeLLM.cancelProto() },
    )
}

@Deprecated("Use RunAnywhere.llm.generateStream(prompt, options).")
fun RunAnywhere.generateStream(request: RALLMGenerateRequest): Flow<RALLMStreamEvent> {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val requestOptions = request.options
    val systemPrompt = requestOptions?.system_prompt
    val systemPromptDesc =
        if (systemPrompt.isNullOrBlank()) {
            "nil"
        } else {
            "set(${systemPrompt.length} chars)"
        }
    llmLogger.info(
        "[PARAMS] generateStream: temperature=${requestOptions?.temperature ?: "default"}, " +
            "topP=${requestOptions?.top_p ?: "default"}, " +
            "maxTokens=${requestOptions?.max_output_tokens ?: "default"}, systemPrompt=$systemPromptDesc",
    )

    return losslessLLMStreamFlow(
        prepare = { ensureServicesReady() },
        generate = { onEvent -> CppBridgeLLM.generateStream(request, onEvent) },
        cancel = { CppBridgeLLM.cancelProto() },
    )
}

/**
 * Adapt the synchronous native LLM callback to a lossless, ordered [Flow].
 *
 * Native backends are allowed to invoke [generate]'s callback synchronously and
 * much faster than a UI collector can render tokens. An unbounded channel keeps
 * that callback non-blocking without dropping events. Delivery failure can now
 * only mean that the collector closed or cancelled the flow; returning `false`
 * immediately tells native generation to stop instead of silently discarding
 * the remainder of the stream.
 *
 * `RALLMStreamEvent.is_final` is deleted outright (idl/llm_service.proto):
 * `event_kind` (COMPLETED/ERROR) is the sole terminal discriminator now,
 * matching Swift's `event.eventKind == .completed || event.eventKind == .error`.
 */
internal fun losslessLLMStreamFlow(
    prepare: suspend () -> Unit,
    generate: suspend (onEvent: (RALLMStreamEvent) -> Boolean) -> Unit,
    cancel: suspend () -> Unit,
): Flow<RALLMStreamEvent> =
    callbackFlow {
        prepare()
        val completedNormally = AtomicBoolean(false)
        val driver =
            launch(Dispatchers.IO) {
                try {
                    generate { event ->
                        val delivered = trySend(event).isSuccess
                        delivered && !event.isTerminal()
                    }
                    completedNormally.set(true)
                } finally {
                    close()
                }
            }
        awaitClose {
            driver.cancel()
            if (!completedNormally.get()) {
                runBlocking { cancel() }
            }
        }
    }.buffer(Channel.UNLIMITED)
        .flowOn(Dispatchers.IO)

private fun RALLMStreamEvent.isTerminal(): Boolean =
    event_kind == LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED ||
        event_kind == LLMStreamEventKind.LLM_STREAM_EVENT_KIND_ERROR

@Deprecated("Cancel the Flow returned by RunAnywhere.llm.generateStream instead.")
suspend fun RunAnywhere.cancelGeneration() {
    if (!isInitialized) return
    try {
        CppBridgeLLM.cancelProto()
    } catch (e: Exception) {
        llmLogger.warning("cancelGeneration failed: ${e.message}")
    }
}

// MARK: - Stream Aggregation

internal data class LLMStreamModelIdentity(
    val modelID: String,
    val framework: String,
)

/**
 * Build a canonical [RALLMGenerationResult] from a [Flow] of [RALLMStreamEvent]s
 * and the currently-loaded LLM model.
 *
 * Mirrors Swift `RunAnywhere.aggregateStream(prompt:events:onToken:)` exactly:
 * concatenates token text, computes TTFT / throughput from wall-clock timestamps,
 * and resolves the framework string from [currentModel] so callers always get
 * the registry's canonical analytics key rather than hardcoding a framework name.
 *
 * @param prompt Prompt text used to estimate [RALLMGenerationResult.input_tokens]
 *   when the backend does not surface it directly.
 * @param events Flow of stream events from [generateStream]. Consumed until
 *   [RALLMStreamEvent.event_kind] reaches COMPLETED/ERROR or the flow completes.
 * @param onThinking Optional callback invoked for each typed thought token with
 *   the accumulated model-emitted reasoning text so far.
 * @param onToken Optional callback invoked for each typed answer token with the
 *   accumulated answer transcript so far.
 * @return A populated [RALLMGenerationResult] whose [RALLMGenerationResult.framework]
 *   matches the loaded LLM model's analytics key; on terminal error events the
 *   [RALLMGenerationResult.error] submessage is propagated.
 */
@Deprecated("Collect RunAnywhere.llm.generateStream and read GenerationEvent.Completed.")
suspend fun RunAnywhere.aggregateStream(
    prompt: String,
    events: Flow<RALLMStreamEvent>,
    onThinking: (suspend (String) -> Unit)? = null,
    onToken: (suspend (String) -> Unit)? = null,
): RALLMGenerationResult =
    aggregateLLMStream(
        prompt = prompt,
        events = events,
        onToken = onToken,
        onThinking = onThinking,
        resolveModelIdentity = {
            val snapshot =
                currentModel(
                    CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_LANGUAGE),
                )
            LLMStreamModelIdentity(
                modelID = if (snapshot.found) snapshot.model_id else "",
                framework =
                    if (snapshot.found) {
                        snapshot.framework.analyticsKey
                    } else {
                        InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN.analyticsKey
                    },
            )
        },
    )

/**
 * Internal, injectable aggregation core used by the public API and unit tests.
 *
 * `RALLMStreamEvent.is_final`/`.kind` (a per-token `TokenKind`) are deleted
 * outright (idl/llm_service.proto): `event_kind` (`LLMStreamEventKind`) is
 * now the sole discriminator, both for terminality (COMPLETED/ERROR) and for
 * routing a token to the thinking vs. answer transcript
 * (THINKING/TOOL_CALL/else), matching Swift's
 * `event.eventKind == .thinking` / `.completed || .error` checks.
 * `LLMGenerationResult.total_time_ms`/`.time_to_first_token_ms`/top-level
 * `ttft_ms` are likewise deleted: `generation_time_ms` (already a `Double`)
 * is the sole wall-clock field left on the result, and TTFT now lives on
 * the shared `TokenUsage.ttft_ms` (`Int64` milliseconds) instead of a
 * top-level `Double`. `TokenUsage.tokens_per_second` was renamed
 * `decode_tokens_per_second`.
 */
/**
 * Batch-style backends (Maple/Bonsai) finish generate before dumping stream
 * chunks. Wall-to-first-token ≈ total, so "decode = total − ttft" is a few ms
 * and produces impossible five-digit tok/s; TTFT also is not a prefill metric.
 * Match commons `compute_stream_timing_metrics` and Plane-B's NpuModelE2ETest.
 */
internal data class SanitizedStreamMetrics(
    val decodeTokensPerSecond: Double,
    val ttftMs: Long,
)

internal fun sanitizeStreamMetrics(
    totalMs: Double,
    outputTokens: Int,
    reportedTps: Double?,
    reportedTtftMs: Long?,
): SanitizedStreamMetrics {
    val wallTps =
        if (totalMs > 0.0 && outputTokens > 0) outputTokens / (totalMs / 1000.0) else 0.0
    val ttft = reportedTtftMs?.takeIf { it > 0L }
    val decodeWindowMs = if (ttft != null) totalMs - ttft.toDouble() else totalMs
    val steadyTps =
        if (ttft != null && decodeWindowMs > 0.0 && outputTokens > 1) {
            (outputTokens - 1) / (decodeWindowMs / 1000.0)
        } else {
            wallTps
        }
    // Batch-buffered: first stream token arrives only after the full generate
    // (Maple/Bonsai), so post-TTFT decode collapses to a few ms. Also catch
    // absurd reported rates even when TTFT was already cleared/zeroed.
    val batchBuffered =
        (ttft != null && decodeWindowMs < maxOf(50.0, totalMs * 0.05)) ||
            (reportedTps != null && reportedTps > maxOf(2_000.0, wallTps * 5.0) && wallTps > 0.0) ||
            (ttft != null && totalMs > 0.0 && ttft.toDouble() >= totalMs * 0.95)
    return if (batchBuffered) {
        // Keep TTFT: for Maple/Bonsai it is time to the first streamed token
        // (first thinking token when reasoning is on). Only tok/s must use wall.
        SanitizedStreamMetrics(decodeTokensPerSecond = wallTps, ttftMs = ttft ?: 0L)
    } else {
        SanitizedStreamMetrics(
            decodeTokensPerSecond = reportedTps?.takeIf { it > 0.0 } ?: steadyTps,
            ttftMs = ttft ?: 0L,
        )
    }
}

internal suspend fun aggregateLLMStream(
    prompt: String,
    events: Flow<RALLMStreamEvent>,
    onToken: (suspend (String) -> Unit)?,
    resolveModelIdentity: suspend () -> LLMStreamModelIdentity,
    nowMillis: () -> Long = System::currentTimeMillis,
    onThinking: (suspend (String) -> Unit)? = null,
): RALLMGenerationResult {
    val answerResponse = StringBuilder()
    val thinkingResponse = StringBuilder()
    var tokenCount = 0
    var firstTokenTimeMs: Long? = null
    val startTimeMs = nowMillis()
    var finishReason = FinishReason.FINISH_REASON_UNSPECIFIED
    var terminalError: ai.runanywhere.proto.v1.SDKError? = null
    var finalEvent: RALLMStreamEvent? = null

    events
        .transformWhile { event ->
            emit(event)
            !event.isTerminal()
        }.collect { event ->
            if (event.token.isNotEmpty()) {
                if (firstTokenTimeMs == null) firstTokenTimeMs = nowMillis()
                tokenCount += 1
                when (event.event_kind) {
                    LLMStreamEventKind.LLM_STREAM_EVENT_KIND_THINKING -> {
                        thinkingResponse.append(event.token)
                        onThinking?.invoke(thinkingResponse.toString())
                    }
                    LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOOL_CALL -> Unit
                    else -> {
                        answerResponse.append(event.token)
                        onToken?.invoke(answerResponse.toString())
                    }
                }
            }
            if (event.isTerminal()) {
                finalEvent = event
                finishReason = event.finish_reason
                terminalError = event.error
            }
        }

    val totalLatencyMs = (nowMillis() - startTimeMs).toDouble()
    val ttftMs = firstTokenTimeMs?.let { (it - startTimeMs) }
    val modelIdentity = resolveModelIdentity()

    // Prefer the backend's terminal aggregate result (text + metrics) when the
    // final event carries one, matching the Web SDK; otherwise fall back to the
    // locally concatenated text / wall-clock metrics.
    val final = finalEvent?.result
    val inputTokens = final?.usage?.input_tokens ?: maxOf(1, prompt.length / 4)
    val tokensGenerated = final?.usage?.output_tokens ?: tokenCount
    val generationTimeMs = final?.generation_time_ms?.takeIf { it > 0.0 } ?: totalLatencyMs
    val metrics =
        sanitizeStreamMetrics(
            totalMs = generationTimeMs,
            outputTokens = tokensGenerated,
            reportedTps = final?.usage?.decode_tokens_per_second,
            reportedTtftMs = final?.usage?.ttft_ms?.takeIf { it > 0L } ?: ttftMs,
        )
    return RALLMGenerationResult(
        text = final?.text ?: answerResponse.toString(),
        thinking_content = final?.thinking_content ?: thinkingResponse.toString().takeIf { it.isNotEmpty() },
        response_tokens = tokensGenerated,
        model_used = modelIdentity.modelID,
        generation_time_ms = generationTimeMs,
        framework = modelIdentity.framework,
        prompt_eval_time_ms =
            if (metrics.ttftMs > 0L) (final?.prompt_eval_time_ms?.takeIf { it > 0L } ?: metrics.ttftMs) else 0L,
        decode_time_ms =
            final?.decode_time_ms?.takeIf { it > 0L }
                ?: if (metrics.ttftMs > 0L && generationTimeMs > metrics.ttftMs) {
                    (generationTimeMs - metrics.ttftMs).toLong()
                } else {
                    generationTimeMs.toLong()
                },
        finish_reason = finishReason,
        error = terminalError,
        usage =
            ai.runanywhere.proto.v1.TokenUsage(
                input_tokens = inputTokens,
                output_tokens = tokensGenerated,
                total_tokens = final?.usage?.total_tokens ?: (inputTokens + tokensGenerated),
                decode_tokens_per_second = metrics.decodeTokensPerSecond,
                ttft_ms = metrics.ttftMs,
            ),
    )
}
