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

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.LLMStreamEvent
import com.runanywhere.sdk.adapters.LLMStreamAdapter
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch

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
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: LLMGenerationOptions()
    val startTime = System.currentTimeMillis()

    val config =
        CppBridgeLLM.GenerationConfig(
            maxTokens = opts.max_tokens,
            temperature = opts.temperature,
            topP = opts.top_p,
            systemPrompt = opts.system_prompt,
        )

    llmLogger.info("[PARAMS] generate: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")

    val cppResult = CppBridgeLLM.generate(prompt, config)

    val endTime = System.currentTimeMillis()
    val latencyMs = (endTime - startTime).toDouble()

    return LLMGenerationResult(
        text = cppResult.text,
        thinking_content = null,
        input_tokens = cppResult.tokensEvaluated - cppResult.tokensGenerated,
        tokens_generated = cppResult.tokensGenerated,
        model_used = CppBridgeLLM.getLoadedModelId() ?: "unknown",
        generation_time_ms = latencyMs,
        framework = "llamacpp",
        tokens_per_second = cppResult.tokensPerSecond.toDouble(),
        ttft_ms = null,
        thinking_tokens = 0,
        response_tokens = cppResult.tokensGenerated,
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
        throw SDKException.notInitialized("SDK not initialized")
    }

    val opts = options ?: LLMGenerationOptions()
    val config =
        CppBridgeLLM.GenerationConfig(
            maxTokens = opts.max_tokens,
            temperature = opts.temperature,
            topP = opts.top_p,
            systemPrompt = opts.system_prompt,
        )

    llmLogger.info("[PARAMS] generateStream: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")

    val handle = CppBridgeLLM.getHandle()
    val adapter = LLMStreamAdapter(handle)

    // Kick off the C++ driver once the collector subscribes so every
    // registered proto collector sees the full token sequence. The driver
    // coroutine re-emits via the C++ dispatcher's proto fan-out; the
    // struct-callback arg is null because we consume events via the
    // adapter, not the per-token struct callback.
    return adapter
        .stream()
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
        }.onCompletion { cause ->
            if (cause != null) {
                CppBridgeLLM.cancel()
            }
        }
}

actual fun RunAnywhere.cancelGeneration() {
    CppBridgeLLM.cancel()
}
