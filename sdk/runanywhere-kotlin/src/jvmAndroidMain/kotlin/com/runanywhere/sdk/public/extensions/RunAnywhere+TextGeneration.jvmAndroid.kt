/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for text generation (LLM) operations.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationResult
import com.runanywhere.sdk.public.extensions.LLM.LLMStreamingResult
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
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
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    val opts = options ?: LLMGenerationOptions.DEFAULT
    val startTime = System.currentTimeMillis()
    llmLogger.debug("Generating response for prompt: ${prompt.take(50)}${if (prompt.length > 50) "..." else ""}")

    // Convert to CppBridgeLLM config
    val config =
        CppBridgeLLM.GenerationConfig(
            maxTokens = opts.maxTokens,
            temperature = opts.temperature,
            topP = opts.topP,
            systemPrompt = opts.systemPrompt,
        )

    llmLogger.info("[PARAMS] generate: temperature=${opts.temperature}, top_p=${opts.topP}, max_tokens=${opts.maxTokens}, system_prompt=${opts.systemPrompt?.let { "set(${it.length} chars)" } ?: "nil"}, streaming=false")

    // Call CppBridgeLLM to generate
    val cppResult = CppBridgeLLM.generate(prompt, config)

    val endTime = System.currentTimeMillis()
    val latencyMs = (endTime - startTime).toDouble()
    llmLogger.info("Generation complete: ${cppResult.tokensGenerated} tokens in ${latencyMs.toLong()}ms (${String.format("%.1f", cppResult.tokensPerSecond)} tok/s)")

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

actual fun RunAnywhere.generateStream(
    prompt: String,
    options: LLMGenerationOptions?,
): Flow<String> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKError.notInitialized("SDK not initialized")
        }

        ensureServicesReady()

        val opts = options ?: LLMGenerationOptions.DEFAULT

        llmLogger.info("[PARAMS] generateStream: temperature=${opts.temperature}, top_p=${opts.topP}, max_tokens=${opts.maxTokens}, system_prompt=${opts.systemPrompt?.let { "set(${it.length} chars)" } ?: "nil"}, streaming=true")

        val config =
            CppBridgeLLM.GenerationConfig(
                maxTokens = opts.maxTokens,
                temperature = opts.temperature,
                topP = opts.topP,
                systemPrompt = opts.systemPrompt,
            )

        // Launch generation on IO dispatcher — tied to this callbackFlow's scope
        val job = launch(Dispatchers.IO) {
            try {
                CppBridgeLLM.generateStream(prompt, config) { token ->
                    trySend(token)
                    true // Continue generation
                }
            } finally {
                channel.close()
            }
        }

        // When collector cancels, cancel both the coroutine and native generation
        awaitClose {
            job.cancel()
            CppBridgeLLM.cancel()
        }
    }

actual suspend fun RunAnywhere.generateStreamWithMetrics(
    prompt: String,
    options: LLMGenerationOptions?,
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

    llmLogger.info("[PARAMS] generateStreamWithMetrics: temperature=${opts.temperature}, top_p=${opts.topP}, max_tokens=${opts.maxTokens}, system_prompt=${opts.systemPrompt?.let { "set(${it.length} chars)" } ?: "nil"}, streaming=true")

    val config =
        CppBridgeLLM.GenerationConfig(
            maxTokens = opts.maxTokens,
            temperature = opts.temperature,
            topP = opts.topP,
            systemPrompt = opts.systemPrompt,
        )

    val tokenStream =
        callbackFlow {
            val job = launch(Dispatchers.IO) {
                try {
                    val cppResult =
                        CppBridgeLLM.generateStream(prompt, config) { token ->
                            if (firstTokenTime == null) {
                                firstTokenTime = System.currentTimeMillis()
                            }
                            fullText += token
                            tokenCount++
                            trySend(token)
                            true // Continue generation
                        }

                    // Build final result after generation completes
                    val endTime = System.currentTimeMillis()
                    val latencyMs = (endTime - startTime).toDouble()
                    val timeToFirstTokenMs = firstTokenTime?.let { (it - startTime).toDouble() }

                    val result =
                        LLMGenerationResult(
                            text = fullText,
                            tokensUsed = tokenCount,
                            modelUsed = CppBridgeLLM.getLoadedModelId() ?: "unknown",
                            latencyMs = latencyMs,
                            framework = "llamacpp",
                            tokensPerSecond = cppResult.tokensPerSecond.toDouble(),
                            timeToFirstTokenMs = timeToFirstTokenMs,
                            responseTokens = tokenCount,
                        )
                    resultDeferred.complete(result)
                } catch (e: Exception) {
                    resultDeferred.completeExceptionally(e)
                } finally {
                    channel.close()
                }
            }

            awaitClose {
                job.cancel()
                CppBridgeLLM.cancel()
            }
        }

    return coroutineScope {
        LLMStreamingResult(
            stream = tokenStream,
            result = async { resultDeferred.await() },
        )
    }
}

actual fun RunAnywhere.cancelGeneration() {
    // Cancel any ongoing generation via CppBridge
    CppBridgeLLM.cancel()
}
