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
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAVLMGenerationRequest
import com.runanywhere.sdk.public.types.RAVLMImage
import com.runanywhere.sdk.public.types.RAVLMResult
import com.runanywhere.sdk.public.types.RAVLMStreamEvent
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import ai.runanywhere.proto.v1.ModelCategory as ProtoModelCategory

// MARK: - Inference

// MARK: - Generation Control

private val vlmLogger = SDKLogger("VLM")
private val vlmNativeRequests = NativeUnaryRequestCoordinator()

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

/**
 * `RAVLMGenerationOptions` was deleted outright (idl/vlm_options.proto);
 * this forwarder's parameter necessarily changes from the deleted options
 * type to the full [RAVLMGenerationRequest] envelope
 * (images/messages/prompt/options/vision) that replaced it. Mirrors
 * Swift's `RunAnywhere.processImage(_ request: RAVLMGenerationRequest)`.
 */
@Deprecated("Use RunAnywhere.vlm.generate(image, prompt, options).")
suspend fun RunAnywhere.processImage(request: RAVLMGenerationRequest): RAVLMResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    if (!isVLMModelLoaded()) {
        throw SDKException.vlm("VLM model not loaded")
    }

    vlmLogger.debug(
        "Processing image with prompt: ${request.prompt.take(50)}${if (request.prompt.length > 50) "..." else ""}",
    )

    val nativeRequest = CppBridgeVLM.prepareProcessRequest(request)
    val result =
        runCancellableNativeUnaryRequest(
            coordinator = vlmNativeRequests,
            request = { requestId -> CppBridgeVLM.processRequestBlocking(requestId, nativeRequest) },
            cancel = CppBridgeVLM::cancelRequest,
        )

    vlmLogger.info(
        "VLM processing complete: ${result.usage?.output_tokens ?: 0} tokens in ${result.total_time_ms}ms " +
            "(${String.format(java.util.Locale.ROOT, "%.1f", result.usage?.decode_tokens_per_second ?: 0.0)} tok/s)",
    )

    return result
}

/**
 * Stream typed [RAVLMStreamEvent]s for a full [RAVLMGenerationRequest].
 *
 * Canonical cross-SDK shape (mirrors Swift
 * `RunAnywhere.processImageStream(_ request:)` returning
 * `AsyncStream<RAVLMStreamEvent>`): STARTED → TOKEN* → exactly one terminal
 * COMPLETED/ERROR. COMPLETED carries the full `VLMResult` with metrics; an
 * ERROR event closes the flow with [SDKException].
 */
@Deprecated("Use RunAnywhere.vlm.generateStream(image, prompt, options).")
fun RunAnywhere.processImageStream(request: RAVLMGenerationRequest): Flow<RAVLMStreamEvent> =
    callbackFlow {
        if (!isInitialized) {
            throw SDKException.notInitialized("SDK not initialized")
        }
        ensureServicesReady()
        if (!isVLMModelLoaded()) {
            throw SDKException.vlm("VLM model not loaded")
        }

        // Unary and streaming VLM share one lifecycle-global native cancel
        // domain, so both must take the same request-scoped lease.
        val nativeRequest =
            CppBridgeVLM.prepareStreamRequest(request) { event ->
                trySend(event)
                when (event.kind) {
                    VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR -> {
                        val message =
                            event.error?.message?.takeIf { it.isNotBlank() }
                                ?: "VLM stream failed"
                        close(SDKException.vlm(message))
                        false
                    }
                    VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED -> {
                        val result = event.result
                        val tokPerSec = result?.usage?.decode_tokens_per_second ?: 0.0
                        vlmLogger.info(
                            "VLM processing complete: ${result?.usage?.output_tokens ?: 0} tokens " +
                                "(${String.format(java.util.Locale.ROOT, "%.1f", tokPerSec)} tok/s)",
                        )
                        true
                    }
                    else -> true
                }
            }
        val job =
            launch {
                try {
                    runCancellableNativeUnaryRequest(
                        coordinator = vlmNativeRequests,
                        request = { requestId ->
                            CppBridgeVLM.processStreamRequestBlocking(requestId, nativeRequest)
                        },
                        cancel = CppBridgeVLM::cancelRequest,
                    )
                    close()
                } catch (e: Exception) {
                    close(e)
                }
            }

        awaitClose {
            job.cancel()
        }
    }

/**
 * Ergonomic overload mirroring Swift `processImageStream(_:prompt:options:)`
 * and React Native: builds the [RAVLMGenerationRequest] envelope from one
 * image + prompt, using default sampling.
 */
@Deprecated("Use RunAnywhere.vlm.generateStream(image, prompt, options).")
fun RunAnywhere.processImageStream(
    image: RAVLMImage,
    prompt: String,
    options: RALLMGenerationOptions = RALLMGenerationOptions.defaults(),
): Flow<RAVLMStreamEvent> =
    processImageStream(
        RAVLMGenerationRequest(images = listOf(image), prompt = prompt, options = options),
    )

// MARK: - Generation Control

@Deprecated("Cancel the Flow returned by RunAnywhere.vlm.generateStream instead.")
suspend fun RunAnywhere.cancelVLMGeneration() {
    vlmNativeRequests.cancelActive()
}
