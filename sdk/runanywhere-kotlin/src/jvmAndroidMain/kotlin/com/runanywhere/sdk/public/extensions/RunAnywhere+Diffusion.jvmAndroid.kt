/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for diffusion (image generation).
 *
 * Round 1 KOTLIN (G-A4): all hand-thrown `unsupportedOperation` stubs
 * have been DELETED. Each method now calls the canonical `racDiffusion*`
 * JNI thunks declared in RunAnywhereBridge. If the C++ side returns
 * RAC_ERROR_FEATURE_NOT_AVAILABLE (Apple-only engine), the SDKException
 * propagates naturally.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DiffusionCapabilities
import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionProgress
import ai.runanywhere.proto.v1.DiffusionResult
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeDiffusionProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext

private fun checkRc(rc: Int, op: String) {
    if (rc != RunAnywhereBridge.RAC_SUCCESS) {
        throw SDKException.operation("$op failed with rc=$rc")
    }
}

actual suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions?,
): DiffusionResult =
    withContext(Dispatchers.IO) {
        if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
        val bytes =
            RunAnywhereBridge.racDiffusionGenerate(prompt, options?.encode())
                ?: throw SDKException.operation("rac_diffusion_generate returned null")
        DiffusionResult.ADAPTER.decode(bytes)
    }

actual suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions?,
    onProgress: (DiffusionProgress) -> Boolean,
): DiffusionResult =
    withContext(Dispatchers.IO) {
        if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
        val listener =
            NativeDiffusionProgressListener { progressBytes ->
                val progress = DiffusionProgress.ADAPTER.decode(progressBytes)
                onProgress(progress)
            }
        val bytes =
            RunAnywhereBridge
                .racDiffusionGenerateWithProgress(prompt, options?.encode(), listener)
                ?: throw SDKException.operation("rac_diffusion_generate returned null")
        DiffusionResult.ADAPTER.decode(bytes)
    }

actual fun RunAnywhere.generateImageStream(
    prompt: String,
    options: DiffusionGenerationOptions?,
): Flow<DiffusionProgress> =
    callbackFlow {
        if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
        var cancelled = false
        val listener =
            NativeDiffusionProgressListener { progressBytes ->
                if (cancelled) return@NativeDiffusionProgressListener false
                val progress = DiffusionProgress.ADAPTER.decode(progressBytes)
                trySend(progress)
                true
            }

        // Drive generation on the calling thread; the JNI thunk blocks until
        // the final progress event has been emitted.
        try {
            RunAnywhereBridge.racDiffusionGenerateWithProgress(prompt, options?.encode(), listener)
            close()
        } catch (t: Throwable) {
            close(t)
        }

        awaitClose { cancelled = true }
    }.flowOn(Dispatchers.IO)

actual suspend fun RunAnywhere.cancelImageGeneration() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        val rc = RunAnywhereBridge.racDiffusionCancel()
        checkRc(rc, "rac_diffusion_cancel")
    }
}

actual suspend fun RunAnywhere.loadDiffusionModel(config: DiffusionConfig) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        val rc =
            RunAnywhereBridge.racDiffusionLoadModel(
                modelPath = config.modelPath,
                modelId = config.modelId,
                modelName = config.modelName,
                configBytes = config.configuration?.encode(),
            )
        checkRc(rc, "rac_diffusion_load_model")
    }
}

actual suspend fun RunAnywhere.unloadDiffusionModel() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        val rc = RunAnywhereBridge.racDiffusionUnloadModel()
        checkRc(rc, "rac_diffusion_unload_model")
    }
}

actual val RunAnywhere.isDiffusionModelLoaded: Boolean
    get() = RunAnywhereBridge.racDiffusionIsModelLoaded()

actual suspend fun RunAnywhere.currentDiffusionModelId(): String? =
    withContext(Dispatchers.IO) {
        RunAnywhereBridge.racDiffusionCurrentModelId()
    }

actual suspend fun RunAnywhere.currentDiffusionFramework(): InferenceFramework? {
    // No dedicated C ABI getter exists yet; the framework is implied by the
    // loaded model and surfaced via getDiffusionCapabilities. Return null
    // until the C++ track exposes it.
    return null
}

actual suspend fun RunAnywhere.getDiffusionCapabilities(): DiffusionCapabilities =
    withContext(Dispatchers.IO) {
        val bytes =
            RunAnywhereBridge.racDiffusionGetCapabilities()
                ?: return@withContext DiffusionCapabilities()
        DiffusionCapabilities.ADAPTER.decode(bytes)
    }
