/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for VLM (Vision Language Model) operations.
 * Mirrors Swift RunAnywhere+VisionLanguage.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVLM
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VLM.VLMGenerationOptions
import com.runanywhere.sdk.public.extensions.VLM.VLMImage
import com.runanywhere.sdk.public.extensions.VLM.VLMImageFormat
import com.runanywhere.sdk.public.extensions.VLM.VLMResult
import com.runanywhere.sdk.public.extensions.VLM.VLMStreamingResult
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch

private val vlmLogger = SDKLogger("VLM")

// MARK: - Simple API

actual suspend fun RunAnywhere.describeImage(
    image: VLMImage,
    prompt: String,
): String {
    val result = processImage(image, prompt, null)
    return result.text
}

// MARK: - Full API

actual suspend fun RunAnywhere.processImage(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions?,
): VLMResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    if (!CppBridgeVLM.isLoaded) {
        throw SDKError.vlm("VLM model not loaded")
    }

    vlmLogger.debug("Processing image with prompt: ${prompt.take(50)}${if (prompt.length > 50) "..." else ""}")

    val optionsJson = options?.let { buildOptionsJson(it) }

    val cppResult = CppBridgeVLM.process(
        imageFormat = image.format.rawValue,
        imagePath = image.filePath,
        imageData = image.pixelData,
        imageBase64 = image.base64Data,
        imageWidth = image.width,
        imageHeight = image.height,
        prompt = prompt,
        optionsJson = optionsJson,
    )

    vlmLogger.info(
        "VLM processing complete: ${cppResult.completionTokens} tokens in ${cppResult.totalTimeMs}ms " +
            "(${String.format("%.1f", cppResult.tokensPerSecond)} tok/s)",
    )

    return cppResult.toVLMResult()
}

actual fun RunAnywhere.processImageStream(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions?,
): Flow<String> =
    flow {
        if (!isInitialized) {
            throw SDKError.notInitialized("SDK not initialized")
        }

        if (!CppBridgeVLM.isLoaded) {
            throw SDKError.vlm("VLM model not loaded")
        }

        val optionsJson = options?.let { buildOptionsJson(it) }

        // Use a channel to bridge callback to flow
        val channel = Channel<String>(Channel.UNLIMITED)

        // Start generation in a separate coroutine
        val scope = CoroutineScope(Dispatchers.IO)
        scope.launch {
            try {
                CppBridgeVLM.processStream(
                    imageFormat = image.format.rawValue,
                    imagePath = image.filePath,
                    imageData = image.pixelData,
                    imageBase64 = image.base64Data,
                    imageWidth = image.width,
                    imageHeight = image.height,
                    prompt = prompt,
                    optionsJson = optionsJson,
                    callback = CppBridgeVLM.StreamCallback { token ->
                        channel.trySend(token)
                        true // Continue generation
                    },
                )
            } finally {
                channel.close()
            }
        }

        // Emit tokens from the channel
        for (token in channel) {
            emit(token)
        }
    }

actual suspend fun RunAnywhere.processImageStreamWithMetrics(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions?,
): VLMStreamingResult {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    if (!CppBridgeVLM.isLoaded) {
        throw SDKError.vlm("VLM model not loaded")
    }

    val optionsJson = options?.let { buildOptionsJson(it) }
    val resultDeferred = CompletableDeferred<VLMResult>()
    val startTime = System.currentTimeMillis()

    var fullText = ""
    var tokenCount = 0
    var firstTokenTime: Long? = null

    // Use a channel to bridge callback to flow
    val channel = Channel<String>(Channel.UNLIMITED)

    // Start generation in a separate coroutine
    val scope = CoroutineScope(Dispatchers.IO)
    scope.launch {
        try {
            val cppResult = CppBridgeVLM.processStream(
                imageFormat = image.format.rawValue,
                imagePath = image.filePath,
                imageData = image.pixelData,
                imageBase64 = image.base64Data,
                imageWidth = image.width,
                imageHeight = image.height,
                prompt = prompt,
                optionsJson = optionsJson,
                callback = CppBridgeVLM.StreamCallback { token ->
                    if (firstTokenTime == null) {
                        firstTokenTime = System.currentTimeMillis()
                    }
                    fullText += token
                    tokenCount++
                    channel.trySend(token)
                    true // Continue generation
                },
            )

            // Build final result after generation completes
            val endTime = System.currentTimeMillis()
            val elapsedMs = endTime - startTime
            val timeToFirstTokenMs = firstTokenTime?.let { it - startTime } ?: 0L

            val result = VLMResult(
                text = fullText,
                promptTokens = cppResult.promptTokens,
                imageTokens = cppResult.imageTokens,
                completionTokens = tokenCount,
                totalTokens = cppResult.promptTokens + tokenCount,
                timeToFirstTokenMs = timeToFirstTokenMs,
                imageEncodeTimeMs = cppResult.imageEncodeTimeMs,
                totalTimeMs = elapsedMs,
                tokensPerSecond = if (elapsedMs > 0) tokenCount * 1000f / elapsedMs else 0f,
            )
            resultDeferred.complete(result)
        } catch (e: Exception) {
            resultDeferred.completeExceptionally(e)
        } finally {
            channel.close()
        }
    }

    val tokenStream =
        flow {
            for (token in channel) {
                emit(token)
            }
        }

    return VLMStreamingResult(
        stream = tokenStream,
        result = scope.async { resultDeferred.await() },
    )
}

// MARK: - Model Management

actual suspend fun RunAnywhere.loadVLMModel(
    modelPath: String,
    mmprojPath: String?,
    modelId: String,
    modelName: String,
) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    vlmLogger.info("Loading VLM model: $modelId from $modelPath")

    val result = CppBridgeVLM.loadModel(modelPath, mmprojPath, modelId, modelName)
    if (result != 0) {
        throw SDKError.vlm("Failed to load VLM model: $modelId (error: $result)")
    }

    vlmLogger.info("VLM model loaded successfully: $modelId")
}

actual suspend fun RunAnywhere.unloadVLMModel() {
    CppBridgeVLM.unload()
    vlmLogger.info("VLM model unloaded")
}

actual val RunAnywhere.isVLMModelLoaded: Boolean
    get() = CppBridgeVLM.isLoaded

// MARK: - Generation Control

actual fun RunAnywhere.cancelVLMGeneration() {
    CppBridgeVLM.cancel()
}

// MARK: - Private Helpers

/**
 * Convert VLM generation options to JSON string for C++ bridge.
 */
private fun buildOptionsJson(options: VLMGenerationOptions): String {
    return buildString {
        append("{")
        append("\"max_tokens\":${options.maxTokens}")
        append(",\"temperature\":${options.temperature}")
        append(",\"top_p\":${options.topP}")
        append(",\"max_image_size\":${options.maxImageSize}")
        append(",\"n_threads\":${options.nThreads}")
        append(",\"use_gpu\":${options.useGpu}")
        options.systemPrompt?.let { prompt ->
            append(",\"system_prompt\":\"${prompt.replace("\"", "\\\"")}\"")
        }
        append("}")
    }
}

/**
 * Convert CppBridgeVLM.ProcessingResult to public VLMResult.
 */
private fun CppBridgeVLM.ProcessingResult.toVLMResult(): VLMResult =
    VLMResult(
        text = text,
        promptTokens = promptTokens,
        imageTokens = imageTokens,
        completionTokens = completionTokens,
        totalTokens = totalTokens,
        timeToFirstTokenMs = timeToFirstTokenMs,
        imageEncodeTimeMs = imageEncodeTimeMs,
        totalTimeMs = totalTimeMs,
        tokensPerSecond = tokensPerSecond,
    )
