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
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.analyticsKey
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RALLMStreamEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

// MARK: - Text Generation

// MARK: - Generation Control

private val llmLogger = SDKLogger.llm

suspend fun RunAnywhere.generate(
    prompt: String,
    options: RALLMGenerationOptions?,
): RALLMGenerationResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: RALLMGenerationOptions()
    llmLogger.info("[PARAMS] generate: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")
    return CppBridgeLLM.generate(prompt, opts)
}

fun RunAnywhere.generateStream(
    prompt: String,
    options: RALLMGenerationOptions?,
): Flow<RALLMStreamEvent> {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val opts = options ?: RALLMGenerationOptions()
    llmLogger.info("[PARAMS] generateStream: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")

    return callbackFlow {
        ensureServicesReady()
        val driver =
            launch(Dispatchers.IO) {
                CppBridgeLLM.generateStream(prompt, opts) { event ->
                    trySend(event)
                    !event.is_final
                }
                close()
            }
        awaitClose {
            driver.cancel()
            runBlocking { CppBridgeLLM.cancelProto() }
        }
    }.flowOn(Dispatchers.IO)
}

fun RunAnywhere.cancelGeneration() {
    runBlocking { CppBridgeLLM.cancelProto() }
}

// MARK: - Stream Aggregation

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
): RALLMGenerationResult {
    var fullResponse = ""
    var tokenCount = 0
    var firstTokenTimeMs: Long? = null
    val startTimeMs = System.currentTimeMillis()
    var finishReason = ""
    var terminalError = ""
    var finalEvent: RALLMStreamEvent? = null

    events.collect { event ->
        if (event.token.isNotEmpty()) {
            if (firstTokenTimeMs == null) firstTokenTimeMs = System.currentTimeMillis()
            fullResponse += event.token
            tokenCount += 1
            onToken?.invoke(fullResponse)
        }
        if (event.is_final) {
            finalEvent = event
            finishReason = event.finish_reason
            terminalError = event.error_message
        }
    }

    val totalLatencyMs = (System.currentTimeMillis() - startTimeMs).toDouble()
    val ttftMs = firstTokenTimeMs?.let { (it - startTimeMs).toDouble() }

    val snapshot =
        currentModel(
            CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_LANGUAGE),
        )
    val modelID = if (snapshot.found) snapshot.model_id else ""
    val framework =
        if (snapshot.found) {
            snapshot.framework.analyticsKey
        } else {
            InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN.analyticsKey
        }

    // Prefer the backend's terminal aggregate result (text + metrics) when the
    // final event carries one, matching the Web SDK; otherwise fall back to the
    // locally concatenated text / wall-clock metrics.
    val final = finalEvent?.result
    return RALLMGenerationResult(
        text = final?.text ?: fullResponse,
        input_tokens = final?.prompt_tokens ?: maxOf(1, prompt.length / 4),
        tokens_generated = final?.completion_tokens ?: tokenCount,
        response_tokens = final?.completion_tokens ?: tokenCount,
        model_used = modelID,
        generation_time_ms = final?.total_time_ms?.toDouble() ?: totalLatencyMs,
        framework = framework,
        tokens_per_second =
            final?.tokens_per_second?.toDouble()
                ?: if (totalLatencyMs > 0) tokenCount / (totalLatencyMs / 1000.0) else 0.0,
        ttft_ms = final?.time_to_first_token_ms?.toDouble() ?: ttftMs,
        finish_reason = finishReason,
        error_message = terminalError.ifEmpty { null },
    )
}
