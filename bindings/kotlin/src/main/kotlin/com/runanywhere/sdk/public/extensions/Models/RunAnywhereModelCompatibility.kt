/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.ErrorCategory
import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelCompatibilityRequest
import ai.runanywhere.proto.v1.ModelCompatibilityResult
import ai.runanywhere.proto.v1.ModelUnloadRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeFileManager
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelCompatibility
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.device.models.domain.PhysicalMemoryProbe
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.public.types.RAModelLoadResult
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException

/** The resource dimensions required before an SDK operation may start. */
internal enum class ModelCompatibilityOperation {
    DOWNLOAD,
    LOAD,
}

/**
 * Check one registered model against the device's current available RAM and
 * free space. The verdict itself is owned by commons; Kotlin only supplies
 * the Android resource probes and decodes the generated proto result.
 */
suspend fun RunAnywhere.checkModelCompatibility(modelId: String): ModelCompatibilityResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    val request =
        ModelCompatibilityRequest(
            model_id = modelId,
            available_ram_bytes = PhysicalMemoryProbe.availablePhysicalMemoryBytes(),
            available_storage_bytes = CppBridgeFileManager.availableSpace(),
        )
    return checkModelCompatibility(request)
}

/** Evaluate a caller-provided canonical compatibility request. */
suspend fun RunAnywhere.checkModelCompatibility(
    request: ModelCompatibilityRequest,
): ModelCompatibilityResult {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }
    val result =
        CppBridgeModelCompatibility.check(request)
            ?: throw SDKException.make(
                code = ErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
                message = "Native model compatibility API unavailable",
                category = ErrorCategory.ERROR_CATEGORY_MODEL,
                shouldLog = false,
            )
    result.error?.let { throw SDKException(it) }
    return result
}

/**
 * Run [action] only after commons approves the resources relevant to
 * [operation]. A load intentionally ignores `can_fit`: an already-downloaded
 * model should not become unloadable merely because disk space later fell.
 *
 * When available RAM is short, one unload-all reclaim is attempted before the
 * hard failure: downloaded STT/LLM weights often remain resident and would
 * otherwise block downloading the next model on mid-range phones.
 */
internal suspend fun <T> withModelCompatibilityPreflight(
    operation: ModelCompatibilityOperation,
    resultProvider: suspend () -> ModelCompatibilityResult,
    reclaimMemory: (suspend () -> Unit)? = { reclaimLoadedModelMemory() },
    action: suspend () -> T,
): T {
    var result = resultProvider()
    var failure = compatibilityFailure(operation, result)
    if (failure?.code == ErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY && reclaimMemory != null) {
        reclaimMemory()
        result = resultProvider()
        failure = compatibilityFailure(operation, result)
    }
    failure?.let { throw it }
    return action()
}

/**
 * The request overload is the lowest public lifecycle entry point. Keep its
 * established result-based failure contract while guaranteeing that native
 * load is never called after an incompatible verdict.
 */
internal suspend fun withModelLoadCompatibilityPreflight(
    request: RAModelLoadRequest,
    resultProvider: suspend () -> ModelCompatibilityResult,
    reclaimMemory: (suspend () -> Unit)? = { reclaimLoadedModelMemory() },
    action: suspend () -> RAModelLoadResult,
): RAModelLoadResult {
    val failure =
        try {
            var result = resultProvider()
            var compatFailure = compatibilityFailure(ModelCompatibilityOperation.LOAD, result)
            if (compatFailure?.code == ErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY &&
                reclaimMemory != null
            ) {
                reclaimMemory()
                result = resultProvider()
                compatFailure = compatibilityFailure(ModelCompatibilityOperation.LOAD, result)
            }
            compatFailure
        } catch (error: SDKException) {
            error
        }
    if (failure != null) {
        return RAModelLoadResult(
            model_id = request.model_id,
            category = request.category ?: ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
            framework =
                request.framework
                    ?: InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED,
            error = failure.error,
        )
    }
    return action()
}

/**
 * Drop every lifecycle-resident model so download/load preflight can re-probe
 * MemAvailable. Best-effort: unit tests and hosts without a live lifecycle
 * simply no-op.
 */
internal suspend fun reclaimLoadedModelMemory() {
    try {
        RunAnywhere.unloadModel(ModelUnloadRequest(unload_all = true))
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        // Best-effort reclaim: ordinary unload failures must not block the retry path.
    }
}

private fun compatibilityFailure(
    operation: ModelCompatibilityOperation,
    result: ModelCompatibilityResult,
): SDKException? {
    if (!result.can_run) {
        return compatibilityException(
            code = ErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY,
            message =
                "${displayModelId(result.model_id)} needs at least " +
                    "${formatGiB(result.required_memory_bytes)} of available memory; " +
                    "${formatGiB(result.available_memory_bytes)} is available. " +
                    "Unload the current model, close other apps, or use a device with more RAM.",
        )
    }
    if (operation == ModelCompatibilityOperation.DOWNLOAD && !result.can_fit) {
        return compatibilityException(
            code = ErrorCode.ERROR_CODE_INSUFFICIENT_STORAGE,
            message =
                "${displayModelId(result.model_id)} needs " +
                    "${formatGiB(result.required_storage_bytes)} of free storage; " +
                    "${formatGiB(result.available_storage_bytes)} is available. " +
                    "Free storage or choose a smaller model.",
        )
    }
    return null
}

private fun compatibilityException(code: ErrorCode, message: String): SDKException =
    SDKException.make(
        code = code,
        message = message,
        category = ErrorCategory.ERROR_CATEGORY_MODEL,
        shouldLog = false,
    )

private fun displayModelId(modelId: String): String =
    modelId.ifBlank { "This model" }

private fun formatGiB(bytes: Long): String =
    String.format(Locale.US, "%.1f GiB", bytes.coerceAtLeast(0L).toDouble() / GIB_BYTES)

private const val GIB_BYTES = 1_073_741_824.0
