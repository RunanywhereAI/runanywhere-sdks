/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for VLM (Vision Language Model) operations.
 * Calls C++ directly via CppBridge.VLM for all operations.
 * Events are emitted by C++ layer via CppEventBridge.
 *
 * Mirrors Swift RunAnywhere+VisionLanguage.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.VLMStreamEventKind
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVLM
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAVLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.sdk.public.types.RAVLMResult
import com.runanywhere.sdk.public.types.RAVLMStreamEvent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory

// MARK: - Inference

// MARK: - Generation Control

private val vlmLogger = SDKLogger("VLM")

/**
 * Returns true if a VLM model is loaded in the lifecycle under either the
 * `MULTIMODAL` or `VISION` category. Mirrors Swift `isVLMModelLoaded()`.
 *
 * Both categories collapse to `SDK_COMPONENT_VLM` in C++ commons. Routes
 * through the public `RunAnywhere.currentModel` API so cross-cutting
 * concerns (telemetry, lifecycle audit) hook in correctly.
 */
private suspend fun RunAnywhere.isVLMModelLoaded(): Boolean {
    for (category in arrayOf(
        ProtoModelCategory.MODEL_CATEGORY_MULTIMODAL,
        ProtoModelCategory.MODEL_CATEGORY_VISION,
    )) {
        if (currentModel(CurrentModelRequest(category = category)).found) {
            return true
        }
    }
    return false
}

// MARK: - Inference

suspend fun RunAnywhere.processImage(
    image: RAVLMImage,
    options: RAVLMGenerationOptions,
): RAVLMResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    if (!isVLMModelLoaded()) {
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

/**
 * Stream typed [RAVLMStreamEvent]s for an image + options request.
 *
 * Canonical cross-SDK shape (mirrors Swift
 * `RunAnywhere.processImageStream(_:options:)` returning
 * `AsyncStream<RAVLMStreamEvent>`): STARTED → TOKEN* → exactly one terminal
 * COMPLETED/ERROR. COMPLETED carries the full `VLMResult` with metrics; an
 * ERROR event closes the flow with [SDKException].
 */
fun RunAnywhere.processImageStream(
    image: RAVLMImage,
    options: RAVLMGenerationOptions,
): Flow<RAVLMStreamEvent> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }
        ensureServicesReady()
        if (!isVLMModelLoaded()) {
            throw SDKException.vlm("VLM model not loaded")
        }

        // Run blocking JNI call on IO dispatcher; callbackFlow handles cancellation
        val job =
            launch(Dispatchers.IO) {
                try {
                    CppBridgeVLM.processStream(image, options) { event ->
                        trySend(event)
                        when (event.kind) {
                            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR -> {
                                val message =
                                    event.error_message?.takeIf { it.isNotBlank() }
                                        ?: "VLM stream failed"
                                close(SDKException.vlm(message))
                                false
                            }
                            VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED -> {
                                val result = event.result
                                vlmLogger.info(
                                    "VLM processing complete: ${result?.completion_tokens ?: 0} tokens " +
                                        "(${String.format(java.util.Locale.ROOT, "%.1f", result?.tokens_per_second ?: 0f)} tok/s)",
                                )
                                true
                            }
                            else -> true
                        }
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

suspend fun RunAnywhere.cancelVLMGeneration() {
    CppBridgeVLM.cancel()
}
