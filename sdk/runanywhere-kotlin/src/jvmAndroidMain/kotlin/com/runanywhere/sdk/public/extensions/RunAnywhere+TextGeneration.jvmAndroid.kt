/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for text generation (LLM) operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationResult
import com.runanywhere.sdk.public.extensions.LLM.LLMStreamingResult
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch

actual suspend fun RunAnywhere.chat(prompt: String): String {
    val result = generate(prompt, null)
    return result.text
}

actual suspend fun RunAnywhere.generate(
    prompt: String,
    options: LLMGenerationOptions?
): LLMGenerationResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: LLMGenerationOptions.DEFAULT
    val startTime = System.currentTimeMillis()

    // Convert to CppBridgeLLM config
    val config = CppBridgeLLM.GenerationConfig(
        maxTokens = opts.maxTokens,
        temperature = opts.temperature,
        topP = opts.topP
    )

    // Call CppBridgeLLM to generate
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
        responseTokens = cppResult.tokensGenerated
    )
}

actual fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions?
): Flow<String> = flow {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val opts = options ?: LLMGenerationOptions.DEFAULT

    val config = CppBridgeLLM.GenerationConfig(
        maxTokens = opts.maxTokens,
        temperature = opts.temperature,
        topP = opts.topP
    )

    // Use a channel to bridge callback to flow
    val channel = Channel<String>(Channel.UNLIMITED)

    // Start generation in a separate coroutine
    val scope = CoroutineScope(Dispatchers.IO)
    scope.launch {
        try {
            CppBridgeLLM.generateStream(prompt, config) { token ->
                channel.trySend(token)
                true // Continue generation
            }
        } finally {
            channel.close()
        }
    }

    // Emit tokens from the channel
    for (token in channel) {
        emit(token)
    }
}

actual suspend fun RunAnywhere.generateStreamWithMetrics(
    prompt: String,
    options: LLMGenerationOptions?
): LLMStreamingResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: LLMGenerationOptions.DEFAULT
    val resultDeferred = CompletableDeferred<LLMGenerationResult>()
    val startTime = System.currentTimeMillis()

    var fullText = ""
    var tokenCount = 0
    var firstTokenTime: Long? = null

    val config = CppBridgeLLM.GenerationConfig(
        maxTokens = opts.maxTokens,
        temperature = opts.temperature,
        topP = opts.topP
    )

    // Use a channel to bridge callback to flow
    val channel = Channel<String>(Channel.UNLIMITED)

    // Start generation in a separate coroutine
    val scope = CoroutineScope(Dispatchers.IO)
    scope.launch {
        try {
            val cppResult = CppBridgeLLM.generateStream(prompt, config) { token ->
                if (firstTokenTime == null) {
                    firstTokenTime = System.currentTimeMillis()
                }
                fullText += token
                tokenCount++
                channel.trySend(token)
                true // Continue generation
            }

            // Build final result after generation completes
            val endTime = System.currentTimeMillis()
            val latencyMs = (endTime - startTime).toDouble()
            val timeToFirstTokenMs = firstTokenTime?.let { (it - startTime).toDouble() }

            val result = LLMGenerationResult(
                text = fullText,
                tokensUsed = tokenCount,
                modelUsed = CppBridgeLLM.getLoadedModelId() ?: "unknown",
                latencyMs = latencyMs,
                framework = "llamacpp",
                tokensPerSecond = cppResult.tokensPerSecond.toDouble(),
                timeToFirstTokenMs = timeToFirstTokenMs,
                responseTokens = tokenCount
            )
            resultDeferred.complete(result)
        } catch (e: Exception) {
            resultDeferred.completeExceptionally(e)
        } finally {
            channel.close()
        }
    }

    val tokenStream = flow {
        for (token in channel) {
            emit(token)
        }
    }

    return LLMStreamingResult(
        stream = tokenStream,
        result = scope.async { resultDeferred.await() }
    )
}
