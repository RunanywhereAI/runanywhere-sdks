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
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.defaults
import com.runanywhere.sdk.foundation.errors.SDKException
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

suspend fun RunAnywhere.generate(
    prompt: String,
    options: RALLMGenerationOptions? = null,
): RALLMGenerationResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: RALLMGenerationOptions.defaults()
    llmLogger.info("[PARAMS] generate: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")
    return CppBridgeLLM.generate(prompt, options)
}

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
            "maxTokens=${requestOptions?.max_tokens ?: "default"}, systemPrompt=$systemPromptDesc, " +
            "streaming=${requestOptions?.streaming_enabled ?: false}",
    )
    return CppBridgeLLM.generate(request)
}

fun RunAnywhere.generateStream(
    prompt: String,
    options: RALLMGenerationOptions? = null,
): Flow<RALLMStreamEvent> {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val opts = options ?: RALLMGenerationOptions.defaults()
    llmLogger.info("[PARAMS] generateStream: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")

    return losslessLLMStreamFlow(
        prepare = { ensureServicesReady() },
        generate = { onEvent -> CppBridgeLLM.generateStream(prompt, options, onEvent) },
        cancel = { CppBridgeLLM.cancelProto() },
    )
}

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
            "maxTokens=${requestOptions?.max_tokens ?: "default"}, systemPrompt=$systemPromptDesc, " +
            "streaming=${requestOptions?.streaming_enabled ?: false}",
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
                        delivered && !event.is_final
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
 *   [RALLMStreamEvent.is_final] is true or the flow completes.
 * @param onToken Optional callback invoked for each non-empty token text with the
 *   accumulated transcript so far (suitable for live UI updates).
 * @return A populated [RALLMGenerationResult] whose [RALLMGenerationResult.framework]
 *   matches the loaded LLM model's analytics key; on terminal error events the
 *   [RALLMGenerationResult.error_message] is propagated.
 */
suspend fun RunAnywhere.aggregateStream(
    prompt: String,
    events: Flow<RALLMStreamEvent>,
    onToken: (suspend (String) -> Unit)? = null,
): RALLMGenerationResult =
    aggregateLLMStream(
        prompt = prompt,
        events = events,
        onToken = onToken,
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

/** Internal, injectable aggregation core used by the public API and unit tests. */
internal suspend fun aggregateLLMStream(
    prompt: String,
    events: Flow<RALLMStreamEvent>,
    onToken: (suspend (String) -> Unit)?,
    resolveModelIdentity: suspend () -> LLMStreamModelIdentity,
    nowMillis: () -> Long = System::currentTimeMillis,
): RALLMGenerationResult {
    val fullResponse = StringBuilder()
    var tokenCount = 0
    var firstTokenTimeMs: Long? = null
    val startTimeMs = nowMillis()
    var finishReason = ""
    var terminalError = ""
    var finalEvent: RALLMStreamEvent? = null

    events
        .transformWhile { event ->
            emit(event)
            !event.is_final
        }.collect { event ->
            if (event.token.isNotEmpty()) {
                if (firstTokenTimeMs == null) firstTokenTimeMs = nowMillis()
                fullResponse.append(event.token)
                tokenCount += 1
                onToken?.invoke(fullResponse.toString())
            }
            if (event.is_final) {
                finalEvent = event
                finishReason = event.finish_reason
                terminalError = event.error_message
            }
        }

    val totalLatencyMs = (nowMillis() - startTimeMs).toDouble()
    val ttftMs = firstTokenTimeMs?.let { (it - startTimeMs).toDouble() }
    val modelIdentity = resolveModelIdentity()

    // Prefer the backend's terminal aggregate result (text + metrics) when the
    // final event carries one, matching the Web SDK; otherwise fall back to the
    // locally concatenated text / wall-clock metrics.
    val final = finalEvent?.result
    val inputTokens = final?.prompt_tokens ?: maxOf(1, prompt.length / 4)
    val tokensGenerated = final?.completion_tokens ?: tokenCount
    return RALLMGenerationResult(
        text = final?.text ?: fullResponse.toString(),
        thinking_content = final?.thinking_content,
        input_tokens = inputTokens,
        tokens_generated = tokensGenerated,
        response_tokens = tokensGenerated,
        total_tokens = final?.total_tokens ?: (inputTokens + tokensGenerated),
        model_used = modelIdentity.modelID,
        generation_time_ms = final?.total_time_ms?.toDouble() ?: totalLatencyMs,
        framework = modelIdentity.framework,
        prompt_eval_time_ms = final?.prompt_eval_time_ms ?: 0L,
        decode_time_ms = final?.decode_time_ms ?: 0L,
        tokens_per_second =
            final?.tokens_per_second?.toDouble()
                ?: if (totalLatencyMs > 0) tokenCount / (totalLatencyMs / 1000.0) else 0.0,
        ttft_ms = final?.time_to_first_token_ms?.toDouble() ?: ttftMs,
        finish_reason = finishReason,
        error_message = terminalError.ifEmpty { null },
    )
}
