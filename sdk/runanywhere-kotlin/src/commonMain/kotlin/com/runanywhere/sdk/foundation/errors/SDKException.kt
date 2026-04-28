/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * SDKException — the canonical Exception wrapper around the proto-generated
 * SDKError message (ai.runanywhere.proto.v1.SDKError). All code throws
 * SDKException; the embedded proto SDKError carries the wire-canonical
 * payload (code, category, message, context, c_abi_code, nested_message).
 *
 * Wave 2 KOTLIN: Legacy `SDKError` data class has been DELETED. SDKException
 * is now the only error type — all factories that existed on the legacy
 * SDKError (stt/tts/vad/vlm/llm/voiceAgent/network/storage/platform/etc.)
 * are mirrored here.
 */

package com.runanywhere.sdk.foundation.errors

import ai.runanywhere.proto.v1.ErrorCategory as ProtoErrorCategory
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode
import ai.runanywhere.proto.v1.SDKError as ProtoSDKError

/**
 * SDKException — Exception subclass that wraps the proto-canonical SDKError.
 *
 * The embedded [error] field is the wire-canonical proto representation of
 * the error and contains:
 *  - `code` (proto ErrorCode, positive magnitude of C ABI code)
 *  - `category` (proto ErrorCategory, coarse routing bucket)
 *  - `message` (human-readable, non-localized)
 *  - `context` (optional source location + telemetry)
 *  - `c_abi_code` (optional negative `rac_result_t` integer for round-tripping)
 *  - `nested_message` (optional underlying-error message)
 *
 * @property error The proto-canonical SDKError wire payload
 */
class SDKException(
    val error: ProtoSDKError,
    cause: Throwable? = null,
) : Exception(error.message, cause) {
    /** The proto error code (positive magnitude of C ABI code). */
    val code: ProtoErrorCode get() = error.code

    /** The proto error category (coarse routing bucket). */
    val category: ProtoErrorCategory get() = error.category

    /** The negative `rac_result_t` integer from the C ABI, if available. */
    val cAbiCode: Int? get() = error.c_abi_code

    /** Optional underlying error message captured at wrap time. */
    val nestedMessage: String? get() = error.nested_message

    override fun toString(): String =
        "SDKException[$category] ${code.name}: ${error.message}"

    companion object {
        // ====================================================================
        // INITIALIZATION FACTORIES
        // ====================================================================

        fun notInitialized(component: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
                category = ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
                message = "$component is not initialized",
                cAbiCode = -100,
                cause = cause,
            )

        fun alreadyInitialized(component: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_ALREADY_INITIALIZED,
                category = ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
                message = "$component is already initialized",
                cAbiCode = -101,
                cause = cause,
            )

        fun invalidConfiguration(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_CONFIGURATION,
                category = ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
                message = message,
                cAbiCode = -103,
                cause = cause,
            )

        fun invalidApiKey(cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_API_KEY,
                category = ProtoErrorCategory.ERROR_CATEGORY_AUTH,
                message = "Invalid API key",
                cAbiCode = -104,
                cause = cause,
            )

        fun invalidArgument(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_ARGUMENT,
                category = ProtoErrorCategory.ERROR_CATEGORY_VALIDATION,
                message = message,
                cAbiCode = -259,
                cause = cause,
            )

        // ====================================================================
        // MODEL FACTORIES
        // ====================================================================

        fun modelNotFound(modelId: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_MODEL_NOT_FOUND,
                category = ProtoErrorCategory.ERROR_CATEGORY_MODEL,
                message = "Model not found: $modelId",
                cAbiCode = -110,
                cause = cause,
            )

        fun modelNotLoaded(modelId: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
                category = ProtoErrorCategory.ERROR_CATEGORY_MODEL,
                message = if (modelId != null) "Model not loaded: $modelId" else "No model is loaded",
                cAbiCode = -116,
                cause = cause,
            )

        fun modelLoadFailed(modelId: String, reason: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_MODEL,
                message = if (reason != null) "Failed to load model $modelId: $reason" else "Failed to load model: $modelId",
                cAbiCode = -111,
                cause = cause,
            )

        // ====================================================================
        // GENERATION FACTORIES (component lifecycle)
        // ====================================================================

        fun generationFailed(reason: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = if (reason != null) "Generation failed: $reason" else "Generation failed",
                cAbiCode = -130,
                cause = cause,
            )

        fun generationTimeout(cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_TIMEOUT,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = "Generation timed out",
                cAbiCode = -131,
                cause = cause,
            )

        // ====================================================================
        // NETWORK FACTORIES
        // ====================================================================

        fun networkUnavailable(cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NETWORK_UNAVAILABLE,
                category = ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
                message = "Network is unavailable",
                cAbiCode = -150,
                cause = cause,
            )

        fun networkError(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NETWORK_ERROR,
                category = ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
                message = message,
                cAbiCode = -151,
                cause = cause,
            )

        fun timeout(operation: String, timeoutMs: Long? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_TIMEOUT,
                category = ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
                message = if (timeoutMs != null) "$operation timed out after ${timeoutMs}ms" else "$operation timed out",
                cAbiCode = -155,
                cause = cause,
            )

        fun downloadFailed(url: String, reason: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
                message = if (reason != null) "Download failed for $url: $reason" else "Download failed: $url",
                cAbiCode = -153,
                cause = cause,
            )

        // ====================================================================
        // STORAGE / FILESYSTEM (IO)
        // ====================================================================

        fun insufficientStorage(requiredBytes: Long? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INSUFFICIENT_STORAGE,
                category = ProtoErrorCategory.ERROR_CATEGORY_IO,
                message =
                    if (requiredBytes != null) {
                        "Insufficient storage space. Required: ${requiredBytes / 1024 / 1024} MB"
                    } else {
                        "Insufficient storage space"
                    },
                cAbiCode = -180,
                cause = cause,
            )

        fun fileNotFound(path: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_FILE_NOT_FOUND,
                category = ProtoErrorCategory.ERROR_CATEGORY_IO,
                message = "File not found: $path",
                cAbiCode = -183,
                cause = cause,
            )

        fun outOfMemory(operation: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY,
                category = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
                message = "Out of memory during: $operation",
                cAbiCode = -221,
                cause = cause,
            )

        // ====================================================================
        // COMPONENT FACTORIES
        // ====================================================================

        fun componentNotReady(component: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_COMPONENT_NOT_READY,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = "Component not ready: $component",
                cAbiCode = -230,
                cause = cause,
            )

        fun invalidState(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -231,
                cause = cause,
            )

        fun cancelled(operation: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_CANCELLED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = "$operation was cancelled",
                cAbiCode = -380,
                cause = cause,
            )

        fun authenticationFailed(reason: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_AUTHENTICATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_AUTH,
                message = if (reason != null) "Authentication failed: $reason" else "Authentication failed",
                cAbiCode = -320,
                cause = cause,
            )

        fun unauthorized(resource: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_UNAUTHORIZED,
                category = ProtoErrorCategory.ERROR_CATEGORY_AUTH,
                message = if (resource != null) "Unauthorized access to: $resource" else "Unauthorized access",
                cAbiCode = -321,
                cause = cause,
            )

        fun unknown(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_UNKNOWN,
                category = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
                message = message,
                cAbiCode = -804,
                cause = cause,
            )

        fun notImplemented(feature: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NOT_IMPLEMENTED,
                category = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
                message = "Not implemented: $feature",
                cAbiCode = -800,
                cause = cause,
            )

        fun unsupportedOperation(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NOT_IMPLEMENTED,
                category = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
                message = message,
                cAbiCode = -800,
                cause = cause,
            )

        // ====================================================================
        // MODALITY FACTORIES (STT/TTS/LLM/VAD/VLM/VoiceAgent)
        //
        // Per errors.proto, modality codes are folded into ERROR_CATEGORY_COMPONENT;
        // modality is recovered downstream from the c_abi_code numeric range.
        // ====================================================================

        fun stt(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -440,
                cause = cause,
            )

        fun tts(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -460,
                cause = cause,
            )

        fun vad(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -480,
                cause = cause,
            )

        fun vlm(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -500,
                cause = cause,
            )

        fun llm(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -420,
                cause = cause,
            )

        fun voiceAgent(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -520,
                cause = cause,
            )

        // ====================================================================
        // CATEGORY FACTORIES (network/storage/platform/download/model/security)
        // ====================================================================

        fun network(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NETWORK_ERROR,
                category = ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
                message = message,
                cAbiCode = -151,
                cause = cause,
            )

        fun storage(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INSUFFICIENT_STORAGE,
                category = ProtoErrorCategory.ERROR_CATEGORY_IO,
                message = message,
                cAbiCode = -180,
                cause = cause,
            )

        fun platform(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_HANDLE,
                category = ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
                message = message,
                cAbiCode = -340,
                cause = cause,
            )

        fun download(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
                message = message,
                cAbiCode = -153,
                cause = cause,
            )

        fun model(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
                category = ProtoErrorCategory.ERROR_CATEGORY_MODEL,
                message = message,
                cAbiCode = -116,
                cause = cause,
            )

        fun securityError(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_UNAUTHORIZED,
                category = ProtoErrorCategory.ERROR_CATEGORY_AUTH,
                message = message,
                cAbiCode = -321,
                cause = cause,
            )

        fun operation(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -130,
                cause = cause,
            )

        // ====================================================================
        // C-ABI INTEROP
        // ====================================================================

        /**
         * Construct an SDKException from a raw C ABI rac_result_t code.
         *
         * @param cAbiCode The negative `rac_result_t` integer from the C ABI
         * @param operation Optional operation name for context
         * @param cause Optional underlying throwable cause
         */
        fun fromCAbiCode(
            cAbiCode: Int,
            operation: String? = null,
            cause: Throwable? = null,
        ): SDKException {
            // Map negative C ABI code to positive proto enum value (absolute magnitude).
            val absMagnitude = if (cAbiCode < 0) -cAbiCode else cAbiCode
            val protoCode = ProtoErrorCode.fromValue(absMagnitude) ?: ProtoErrorCode.ERROR_CODE_UNKNOWN
            val category = inferCategory(protoCode)
            val baseMessage = operation?.let { "$it failed" } ?: "Operation failed"
            val message = "$baseMessage (rac_result_t=$cAbiCode, code=${protoCode.name})"
            return of(
                code = protoCode,
                category = category,
                message = message,
                cAbiCode = if (cAbiCode < 0) cAbiCode else null,
                cause = cause,
            )
        }

        /**
         * Infer the proto ErrorCategory from a proto ErrorCode based on the
         * numeric value range. Per errors.proto, modality codes (STT/TTS/LLM/
         * VAD/VLM) are folded into ERROR_CATEGORY_COMPONENT — modality is
         * recovered from the c_abi_code numeric range.
         */
        private fun inferCategory(code: ProtoErrorCode): ProtoErrorCategory {
            return when (code.value) {
                in 100..109 -> ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION
                in 110..129 -> ProtoErrorCategory.ERROR_CATEGORY_MODEL
                in 130..149 -> ProtoErrorCategory.ERROR_CATEGORY_COMPONENT
                in 150..179 -> ProtoErrorCategory.ERROR_CATEGORY_NETWORK
                in 180..219 -> ProtoErrorCategory.ERROR_CATEGORY_IO
                in 220..229 -> ProtoErrorCategory.ERROR_CATEGORY_INTERNAL
                in 230..249 -> ProtoErrorCategory.ERROR_CATEGORY_COMPONENT
                in 250..279 -> ProtoErrorCategory.ERROR_CATEGORY_VALIDATION
                in 280..299 -> ProtoErrorCategory.ERROR_CATEGORY_IO
                in 300..319 -> ProtoErrorCategory.ERROR_CATEGORY_COMPONENT
                in 320..329 -> ProtoErrorCategory.ERROR_CATEGORY_AUTH
                in 330..349 -> ProtoErrorCategory.ERROR_CATEGORY_INTERNAL
                in 350..369 -> ProtoErrorCategory.ERROR_CATEGORY_IO
                in 370..379 -> ProtoErrorCategory.ERROR_CATEGORY_COMPONENT
                in 380..389 -> ProtoErrorCategory.ERROR_CATEGORY_COMPONENT
                in 400..499 -> ProtoErrorCategory.ERROR_CATEGORY_COMPONENT
                in 500..599 -> ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION
                in 600..699 -> ProtoErrorCategory.ERROR_CATEGORY_COMPONENT
                in 700..799 -> ProtoErrorCategory.ERROR_CATEGORY_COMPONENT
                else -> ProtoErrorCategory.ERROR_CATEGORY_INTERNAL
            }
        }

        /**
         * Internal helper to construct an SDKException with all fields set.
         */
        private fun of(
            code: ProtoErrorCode,
            category: ProtoErrorCategory,
            message: String,
            cAbiCode: Int? = null,
            cause: Throwable? = null,
        ): SDKException =
            SDKException(
                error =
                    ProtoSDKError(
                        code = code,
                        category = category,
                        message = message,
                        c_abi_code = cAbiCode,
                        nested_message = cause?.message,
                    ),
                cause = cause,
            )
    }
}

// See `Int.toSDKException` and `Int.throwIfCAbiErrorAsException` extensions
// at the bottom of CommonsErrorMapping.kt for proto-canonical equivalents.
