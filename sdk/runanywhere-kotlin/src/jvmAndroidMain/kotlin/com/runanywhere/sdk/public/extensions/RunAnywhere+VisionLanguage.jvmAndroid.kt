/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for VLM (Vision Language Model) operations.
 * Mirrors Swift RunAnywhere+VisionLanguage.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMResult
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVLMProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
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

actual suspend fun RunAnywhere.askAboutImage(
    question: String,
    image: VLMImage,
): String {
    // Per canonical §7: askAboutImage(question, image) is a convenience
    // over processImage with the question as the prompt.
    val result = processImage(image, question, null)
    return result.text
}

// MARK: - Full API

actual suspend fun RunAnywhere.processImage(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions?,
): VLMResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    if (!CppBridgeVLMProto.isLoaded()) {
        throw SDKException.vlm("VLM model not loaded")
    }

    vlmLogger.debug("Processing image with prompt: ${prompt.take(50)}${if (prompt.length > 50) "..." else ""}")

    val result = CppBridgeVLMProto.process(image, (options ?: VLMGenerationOptions()).copy(prompt = prompt))

    vlmLogger.info(
        "VLM processing complete: ${result.completion_tokens} tokens in ${result.processing_time_ms}ms " +
            "(${String.format(java.util.Locale.ROOT, "%.1f", result.tokens_per_second)} tok/s)",
    )

    return result
}

actual fun RunAnywhere.processImageStream(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions?,
): Flow<String> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        ensureServicesReady()

        if (!CppBridgeVLMProto.isLoaded()) {
            throw SDKException.vlm("VLM model not loaded")
        }

        // Run blocking JNI call on IO dispatcher; callbackFlow handles cancellation
        val job =
            launch(Dispatchers.IO) {
                try {
                    val result =
                        CppBridgeVLMProto.processStream(
                            image,
                            (options ?: VLMGenerationOptions()).copy(prompt = prompt),
                        ) { true }
                    trySend(result.text)
                    close()
                } catch (e: Exception) {
                    close(e)
                }
            }

        awaitClose {
            CppBridgeVLMProto.cancel()
            job.cancel()
        }
    }

actual suspend fun RunAnywhere.processImageStreamWithMetrics(
    image: VLMImage,
    prompt: String,
    options: VLMGenerationOptions?,
): VLMStreamingResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    if (!CppBridgeVLMProto.isLoaded()) {
        throw SDKException.vlm("VLM model not loaded")
    }

    val resultDeferred = CompletableDeferred<VLMResult>()

    val tokenStream =
        callbackFlow {
            val job =
                launch(Dispatchers.IO) {
                    try {
                        val result =
                            CppBridgeVLMProto.processStream(
                                image,
                                (options ?: VLMGenerationOptions()).copy(prompt = prompt),
                            ) { true }
                        trySend(result.text)
                        resultDeferred.complete(result)
                        close()
                    } catch (e: Exception) {
                        resultDeferred.completeExceptionally(e)
                        close(e)
                    }
                }
            awaitClose {
                CppBridgeVLMProto.cancel()
                job.cancel()
            }
        }

    return VLMStreamingResult(
        stream = tokenStream,
        result = resultDeferred,
    )
}

// MARK: - Model Management

actual suspend fun RunAnywhere.loadVLMModel(modelId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    vlmLogger.info("Loading VLM model by ID: $modelId")

    val result = CppBridgeVLMProto.loadModelById(modelId)
    if (result != 0) {
        throw SDKException.vlm("Failed to load VLM model: $modelId (error: $result)")
    }

    vlmLogger.info("VLM model loaded successfully by ID: $modelId")
}

actual suspend fun RunAnywhere.loadVLMModel(
    modelPath: String,
    mmprojPath: String?,
    modelId: String,
    modelName: String,
) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    vlmLogger.info("Loading VLM model: $modelId from $modelPath")

    val result = CppBridgeVLMProto.loadModel(modelPath, mmprojPath, modelId)
    if (result != 0) {
        throw SDKException.vlm("Failed to load VLM model: $modelId (error: $result)")
    }

    vlmLogger.info("VLM model loaded successfully: $modelId")
}

actual suspend fun RunAnywhere.unloadVLMModel() {
    CppBridgeVLMProto.destroy()
    vlmLogger.info("VLM model unloaded")
}

actual val RunAnywhere.isVLMModelLoaded: Boolean
    get() = CppBridgeVLMProto.isLoaded()

actual val RunAnywhere.currentVLMModelId: String?
    get() = CppBridgeVLMProto.modelId()

// MARK: - Generation Control

actual fun RunAnywhere.cancelVLMGeneration() {
    CppBridgeVLMProto.cancel()
}
