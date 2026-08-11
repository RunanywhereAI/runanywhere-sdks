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

import ai.runanywhere.proto.v1.LLMStreamEventKind
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
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
