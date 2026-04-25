/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for text generation (LLM).
 *
 * v2 close-out Phase G-2: the hand-rolled `callbackFlow { CppBridgeLLM.generateStream(...)
 * { token -> trySend(token) } }` shim and `generateStreamWithMetrics`
 * variant were DELETED. The public `generateStream` now delegates to
 * [`LLMStreamAdapter`] which owns the single
 * `rac_llm_set_stream_proto_callback` registration for the handle.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.LLMStreamEvent
import com.runanywhere.sdk.adapters.LLMStreamAdapter
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob

private val llmLogger = SDKLogger.llm

actual suspend fun RunAnywhere.chat(prompt: String): String {
    val result = generate(prompt, null)
    return result.text
}

actual suspend fun RunAnywhere.generate(
    prompt: String,
    options: LLMGenerationOptions?,
): LLMGenerationResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: LLMGenerationOptions.DEFAULT
    val startTime = System.currentTimeMillis()

    val config =
        CppBridgeLLM.GenerationConfig(
            maxTokens = opts.maxTokens,
            temperature = opts.temperature,
            topP = opts.topP,
            systemPrompt = opts.systemPrompt,
        )

    llmLogger.info("[PARAMS] generate: temperature=${opts.temperature}, top_p=${opts.topP}, max_tokens=${opts.maxTokens}")

    val cppResult = CppBridgeLLM.generate(prompt, config)

    val endTime = System.currentTimeMillis()
    val latencyMs = (endTime - startTime).toDouble()

    return LLMGenerationResult(
        text = cppResult.text,
        thinkingContent = null,
        inputTokens = cppResult.tokensEvaluated - cppResult.tokensGenerated,
        tokensUsed = cppResult.tokensGenerated,
        modelUsed = CppBridgeLLM.getLoadedModelId() ?: "unknown",
        latencyMs = latencyMs,
        framework = "llamacpp",
        tokensPerSecond = cppResult.tokensPerSecond.toDouble(),
        timeToFirstTokenMs = null,
        thinkingTokens = null,
        responseTokens = cppResult.tokensGenerated,
    )
}

// Dedicated scope for the background C++ driver launched by generateStream.
// The collector's lifetime (via LLMStreamAdapter's callbackFlow awaitClose)
// controls when the adapter unregisters; this scope just keeps the C++
// call alive and lets `CppBridgeLLM.cancel()` abort it cooperatively.
private val llmStreamDriverScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

actual fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions?,
): Flow<LLMStreamEvent> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val opts = options ?: LLMGenerationOptions.DEFAULT
    val config =
        CppBridgeLLM.GenerationConfig(
            maxTokens = opts.maxTokens,
            temperature = opts.temperature,
            topP = opts.topP,
            systemPrompt = opts.systemPrompt,
        )

    llmLogger.info("[PARAMS] generateStream: temperature=${opts.temperature}, top_p=${opts.topP}, max_tokens=${opts.maxTokens}")

    val handle = CppBridgeLLM.getHandle()
    val adapter = LLMStreamAdapter(handle)

    // Kick off the C++ driver once the collector subscribes so every
    // registered proto collector sees the full token sequence. The driver
    // coroutine re-emits via the C++ dispatcher's proto fan-out; the
    // struct-callback arg is null because we consume events via the
    // adapter, not the per-token struct callback.
    return adapter.stream()
        .onStart {
            llmStreamDriverScope.launch {
                try {
                    CppBridgeLLM.generateStream(prompt, config) { _ ->
                        /* No-op: events are delivered to the collector via
                         * the proto-byte callback set by LLMStreamAdapter.
                         * Returning true keeps the C++ loop running. */
                        true
                    }
                } catch (e: Throwable) {
                    llmLogger.warn("generateStream driver failed: ${e.message}")
                }
            }
        }
        .onCompletion { cause ->
            if (cause != null) {
                CppBridgeLLM.cancel()
            }
        }
}

actual fun RunAnywhere.cancelGeneration() {
    CppBridgeLLM.cancel()
}
