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
import ai.runanywhere.proto.v1.DiffusionConfig
import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionProgress
import ai.runanywhere.proto.v1.DiffusionResult
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDiffusionProto
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext

actual suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions?,
): DiffusionResult =
    withContext(Dispatchers.IO) {
        if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
        CppBridgeDiffusionProto.generate(prompt, options)
    }

actual suspend fun RunAnywhere.generateImage(
    prompt: String,
    options: DiffusionGenerationOptions?,
    onProgress: (DiffusionProgress) -> Boolean,
): DiffusionResult =
    withContext(Dispatchers.IO) {
        if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
        CppBridgeDiffusionProto.generateWithProgress(prompt, options, onProgress)
    }

actual fun RunAnywhere.generateImageStream(
    prompt: String,
    options: DiffusionGenerationOptions?,
): Flow<DiffusionProgress> =
    callbackFlow {
        if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
        var cancelled = false

        // Drive generation on the calling thread; the JNI thunk blocks until
        // the final progress event has been emitted.
        try {
            CppBridgeDiffusionProto.generateWithProgress(prompt, options) progress@ { progress ->
                if (cancelled) return@progress false
                trySend(progress)
                true
            }
            close()
        } catch (t: Throwable) {
            close(t)
        }

        awaitClose { cancelled = true }
    }.flowOn(Dispatchers.IO)

actual suspend fun RunAnywhere.cancelImageGeneration() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeDiffusionProto.cancel()
    }
}

actual suspend fun RunAnywhere.loadDiffusionModel(config: DiffusionConfig) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeDiffusionProto.load(config)
    }
}

actual suspend fun RunAnywhere.unloadDiffusionModel() {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    withContext(Dispatchers.IO) {
        CppBridgeDiffusionProto.unload()
    }
}

actual val RunAnywhere.isDiffusionModelLoaded: Boolean
    get() = CppBridgeDiffusionProto.isLoaded()

actual suspend fun RunAnywhere.currentDiffusionModelId(): String? =
    withContext(Dispatchers.IO) {
        CppBridgeDiffusionProto.currentModelId()
    }

actual suspend fun RunAnywhere.currentDiffusionFramework(): InferenceFramework? {
    // No dedicated C ABI getter exists yet; the framework is implied by the
    // loaded model and surfaced via getDiffusionCapabilities. Return null
    // until the C++ track exposes it.
    return null
}

actual suspend fun RunAnywhere.getDiffusionCapabilities(): DiffusionCapabilities =
    withContext(Dispatchers.IO) {
        CppBridgeDiffusionProto.capabilities()
    }
