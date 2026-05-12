/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for text generation (LLM).
 *
 * Public generation now delegates to the generated-proto LLM service ABI.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
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

private val llmLogger = SDKLogger.llm

actual suspend fun RunAnywhere.generate(
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

actual fun RunAnywhere.generateStream(
    prompt: String,
    options: RALLMGenerationOptions?,
): Flow<RALLMStreamEvent> {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val opts = options ?: RALLMGenerationOptions()
    llmLogger.info("[PARAMS] generateStream: temperature=${opts.temperature}, topP=${opts.top_p}, maxTokens=${opts.max_tokens}")

    return callbackFlow {
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
            runBlocking { CppBridgeLLM.cancel() }
        }
    }.flowOn(Dispatchers.IO)
}

actual fun RunAnywhere.cancelGeneration() {
    runBlocking { CppBridgeLLM.cancel() }
}
