/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for text generation (LLM).
 *
 * Public generation now delegates to the generated-proto LLM service ABI.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.LLMStreamEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLMProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
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
    llmLogger.info("[PARAMS] generate: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")
    return CppBridgeLLMProto.generate(prompt, opts)
}

actual fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions?,
): Flow<LLMStreamEvent> {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val opts = options ?: LLMGenerationOptions()
    llmLogger.info("[PARAMS] generateStream: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")

    return callbackFlow {
        val driver =
            launch(Dispatchers.IO) {
                CppBridgeLLMProto.generateStream(prompt, opts) { event ->
                    trySend(event)
                    !event.is_final
                }
                close()
            }
        awaitClose {
            driver.cancel()
            CppBridgeLLMProto.cancel()
        }
    }.flowOn(Dispatchers.IO)
}

actual fun RunAnywhere.cancelGeneration() {
    CppBridgeLLMProto.cancel()
}
