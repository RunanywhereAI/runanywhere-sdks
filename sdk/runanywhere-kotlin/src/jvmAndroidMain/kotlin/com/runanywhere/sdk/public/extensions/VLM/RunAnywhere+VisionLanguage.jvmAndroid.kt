/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for VLM (Vision Language Model) operations.
 * Mirrors Swift RunAnywhere+VisionLanguage.swift exactly.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.CurrentModelResult
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.ModelLoadRequest
import ai.runanywhere.proto.v1.ModelLoadResult
import ai.runanywhere.proto.v1.ModelUnloadRequest
import ai.runanywhere.proto.v1.SDKEvent
import ai.runanywhere.proto.v1.VLMGenerationOptions
import ai.runanywhere.proto.v1.VLMImage
import ai.runanywhere.proto.v1.VLMResult
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelLifecycleProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeVLMProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.resolvedPrimaryModelPath
import com.runanywhere.sdk.public.extensions.Models.resolvedVisionProjectorPath
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch

private val vlmLogger = SDKLogger("VLM")
private val vlmLifecycleCategories =
    listOf(
        ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        ModelCategory.MODEL_CATEGORY_VISION,
    )

private data class ResolvedVLMArtifacts(
    val primaryModelPath: String,
    val visionProjectorPath: String,
)

private fun ModelLoadResult.requireVLMArtifacts(requestedModelId: String): ResolvedVLMArtifacts {
    val primaryPath =
        resolvedPrimaryModelPath()
            ?: throw SDKException.vlm(
                "Native lifecycle did not resolve a primary VLM artifact for '$requestedModelId'",
            )
    val projectorPath =
        resolvedVisionProjectorPath()
            ?: throw SDKException.vlm(
                "Native lifecycle did not resolve a vision projector artifact for '$requestedModelId'",
            )
    return ResolvedVLMArtifacts(primaryPath, projectorPath)
}

private fun CurrentModelResult.hasVLMArtifacts(): Boolean =
    resolvedPrimaryModelPath() != null && resolvedVisionProjectorPath() != null

private fun currentVLMModelFromLifecycle(): CurrentModelResult? =
    try {
        vlmLifecycleCategories.firstNotNullOfOrNull { category ->
            CppBridgeModelLifecycleProto
                .currentModel(CurrentModelRequest(category = category))
                ?.takeIf { it.found && it.hasVLMArtifacts() }
        }
    } catch (e: Throwable) {
        vlmLogger.warn("Unable to read current VLM lifecycle state: ${e.message}")
        null
    }

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
): Flow<SDKEvent> =
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
                    CppBridgeVLMProto.processStream(
                        image,
                        (options ?: VLMGenerationOptions()).copy(prompt = prompt),
                    ) { event ->
                        trySend(event)
                        true
                    }
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

// MARK: - Model Management

actual suspend fun RunAnywhere.loadVLMModel(modelId: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    ensureServicesReady()

    vlmLogger.info("Loading VLM model through lifecycle: $modelId")

    CppBridgeVLMProto.destroy()

    val lifecycleResult = loadModel(ModelLoadRequest(model_id = modelId))
    if (!lifecycleResult.success) {
        throw SDKException.vlm(
            lifecycleResult.error_message.ifBlank { "Failed to load VLM model '$modelId'" },
        )
    }

    val artifacts = lifecycleResult.requireVLMArtifacts(modelId)
    val resolvedModelId = lifecycleResult.model_id.ifBlank { modelId }

    val result =
        CppBridgeVLMProto.loadResolvedArtifacts(
            modelId = resolvedModelId,
            primaryModelPath = artifacts.primaryModelPath,
            visionProjectorPath = artifacts.visionProjectorPath,
        )
    if (result != 0) {
        unloadLifecycleVLMQuietly(resolvedModelId)
        throw SDKException.vlm("Failed to load VLM model: $modelId (error: $result)")
    }

    vlmLogger.info("VLM model loaded successfully: $resolvedModelId")
}

actual suspend fun RunAnywhere.unloadVLMModel() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    val current = currentVLMModelFromLifecycle()
    CppBridgeVLMProto.destroy()
    current?.model_id?.takeIf { it.isNotBlank() }?.let { modelId ->
        val result = unloadModel(ModelUnloadRequest(model_id = modelId))
        if (!result.success) {
            throw SDKException.vlm(
                result.error_message.ifBlank { "Failed to unload VLM model '$modelId'" },
            )
        }
    }
    vlmLogger.info("VLM model unloaded")
}

actual val RunAnywhere.isVLMModelLoaded: Boolean
    get() = CppBridgeVLMProto.isLoaded() && currentVLMModelFromLifecycle() != null

actual val RunAnywhere.currentVLMModelId: String?
    get() = currentVLMModelFromLifecycle()?.model_id

// MARK: - Generation Control

actual fun RunAnywhere.cancelVLMGeneration() {
    CppBridgeVLMProto.cancel()
}

private suspend fun RunAnywhere.unloadLifecycleVLMQuietly(modelId: String) {
    try {
        unloadModel(ModelUnloadRequest(model_id = modelId))
    } catch (e: Exception) {
        vlmLogger.warn("Failed to clean up lifecycle VLM model '$modelId': ${e.message}")
    }
}

// MARK: - VLM Models

actual suspend fun RunAnywhere.loadVLMModelInfo(model: ModelInfo) {
    loadVLMModel(model.id)
}

actual suspend fun RunAnywhere.loadVLMModelById(modelId: String) {
    loadVLMModel(modelId)
}
