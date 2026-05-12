/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for VLM (Vision Language Model) operations.
 * Mirrors Swift RunAnywhere+VisionLanguage.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVLM
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RASDKEvent
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.sdk.public.types.RAVLMResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch

private val vlmLogger = SDKLogger("VLM")

// MARK: - Inference

actual suspend fun RunAnywhere.processImage(
    image: RAVLMImage,
    options: RAVLMGenerationOptions,
): RAVLMResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    if (!CppBridgeVLM.isLoaded()) {
        throw SDKException.vlm("VLM model not loaded")
    }

    vlmLogger.debug(
        "Processing image with prompt: ${options.prompt.take(50)}${if (options.prompt.length > 50) "..." else ""}",
    )

    val result = CppBridgeVLM.process(image, options)

    vlmLogger.info(
        "VLM processing complete: ${result.completion_tokens} tokens in ${result.processing_time_ms}ms " +
            "(${String.format(java.util.Locale.ROOT, "%.1f", result.tokens_per_second)} tok/s)",
    )

    return result
}

actual fun RunAnywhere.processImageStream(
    image: RAVLMImage,
    options: RAVLMGenerationOptions,
): Flow<RASDKEvent> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }

        ensureServicesReady()

        if (!CppBridgeVLM.isLoaded()) {
            throw SDKException.vlm("VLM model not loaded")
        }

        // Run blocking JNI call on IO dispatcher; callbackFlow handles cancellation
        val job =
            launch(Dispatchers.IO) {
                try {
                    CppBridgeVLM.processStream(image, options) { event ->
                        trySend(event)
                        true
                    }
                    close()
                } catch (e: Exception) {
                    close(e)
                }
            }

        awaitClose {
            CppBridgeVLM.cancel()
            job.cancel()
        }
    }

// MARK: - Generation Control

actual fun RunAnywhere.cancelVLMGeneration() {
    CppBridgeVLM.cancel()
}
