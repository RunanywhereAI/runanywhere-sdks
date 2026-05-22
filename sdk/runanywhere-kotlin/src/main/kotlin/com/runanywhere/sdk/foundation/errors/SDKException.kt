/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * SDKException — the canonical Exception wrapper around the proto-generated
 * SDKError message (ai.runanywhere.proto.v1.SDKError). All code throws
 * SDKException; the embedded proto SDKError carries the wire-canonical
 * payload (code, category, message, context, c_abi_code, nested_message).
 */

package com.runanywhere.sdk.foundation.errors

import com.runanywhere.sdk.infrastructure.logging.Logging
import com.runanywhere.sdk.public.extensions.LogLevel
import ai.runanywhere.proto.v1.ErrorCategory as ProtoErrorCategory
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode
import ai.runanywhere.proto.v1.ErrorContext as ProtoErrorContext
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

    /**
     * Dot-separated path to the field that triggered a validation failure
     * (e.g. `"STTOptions.sample_rate"`). Populated by the generated
     * `validate()` helpers under `commonMain/.../generated/convenience/`
     * so callers can programmatically identify the failing field without
     * parsing the human-readable message.
     *
     * Backed by `error.context.metadata["field_path"]` — the wire-canonical
     * carrier shared with Swift / Dart / TS.
     */
    val fieldPath: String? get() = error.context?.metadata?.get("field_path")

    override fun toString(): String =
        "SDKException[$category] ${code.name}: ${error.message}"

    companion object {
        // ====================================================================
        // GENERIC FACTORY (Swift parity: SDKException.make(...))
        // ====================================================================

        /**
         * Generic factory; auto-logs unexpected errors unless [shouldLog] is
         * false or the [code] is classified as expected (e.g.
         * `ERROR_CODE_CANCELLED`, `ERROR_CODE_STREAM_CANCELLED`).
         *
         * Mirrors Swift's `SDKException.make(code:message:category:underlying:shouldLog:)`.
         *
         * @param code     The proto error code (positive magnitude of C ABI code).
         * @param message  Human-readable, non-localized error message.
         * @param category Coarse routing bucket. Defaults to
         *                 [ProtoErrorCategory.ERROR_CATEGORY_COMPONENT].
         * @param cAbiCode Optional negative `rac_result_t` integer from the C ABI.
         * @param cause    Optional underlying [Throwable] cause.
         * @param shouldLog When true (default), routes the exception through
         *                  [Logging] unless the code is classified as expected.
         */
        fun make(
            code: ProtoErrorCode,
            message: String,
            category: ProtoErrorCategory = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
            cAbiCode: Int? = null,
            cause: Throwable? = null,
            shouldLog: Boolean = true,
        ): SDKException {
            val ex = of(code = code, category = category, message = message, cAbiCode = cAbiCode, cause = cause)
            if (shouldLog && !code.isExpected) {
                ex.log()
            }
            return ex
        }

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

        fun validationFailed(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_VALIDATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_VALIDATION,
                message = message,
                cAbiCode = -250,
                cause = cause,
            )

        /**
         * Validation failure with a structured `fieldPath` discriminant
         * (e.g. `"STTOptions.sample_rate"`). Mirrors the canonical shape
         * emitted by `idl/codegen/generate_*_convenience.py`: every SDK
         * throws `{ code, category, fieldPath, message }`.
         *
         * Mirrors Swift's identical factory at SDKException.swift:196-222
         * which auto-logs the exception via `ex.log()` when the code is
         * not classified as expected. Validation failures (proto code
         * `ERROR_CODE_INVALID_ARGUMENT`) are never expected, so this path
         * always emits an ERROR-level log entry — keeping Kotlin / Swift
         * telemetry symmetric for the same misconfigured input.
         */
        fun validationFailed(
            fieldPath: String,
            message: String,
            cause: Throwable? = null,
        ): SDKException {
            val ex =
                SDKException(
                    error =
                        ProtoSDKError(
                            code = ProtoErrorCode.ERROR_CODE_INVALID_ARGUMENT,
                            category = ProtoErrorCategory.ERROR_CATEGORY_VALIDATION,
                            message = message,
                            context =
                                ProtoErrorContext(
                                    metadata = mapOf("field_path" to fieldPath),
                                ),
                            c_abi_code = -259,
                            nested_message = cause?.message,
                        ),
                    cause = cause,
                )
            if (!ProtoErrorCode.ERROR_CODE_INVALID_ARGUMENT.isExpected) {
                ex.log()
            }
            return ex
        }

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
        // NETWORK FACTORIES
        // ====================================================================

        fun networkError(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NETWORK_ERROR,
                category = ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
                message = message,
                cAbiCode = -151,
                cause = cause,
            )

        // ====================================================================
        // COMPONENT FACTORIES
        // ====================================================================

        fun invalidState(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_STATE,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -231,
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

        fun notImplemented(feature: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NOT_IMPLEMENTED,
                category = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
                message = "Not implemented: $feature",
                cAbiCode = -800,
                cause = cause,
            )

        // ====================================================================
        // MODALITY FACTORIES (STT/TTS/LLM/VAD/VLM/VoiceAgent)
        //
        // Per errors.proto, modality codes are folded into ERROR_CATEGORY_COMPONENT;
        // modality is recovered downstream from the c_abi_code numeric range.
        // ====================================================================

        fun tts(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -460,
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

        fun voiceAgent(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cAbiCode = -520,
                cause = cause,
            )

        // ====================================================================
        // CATEGORY FACTORIES (storage/platform/model/operation)
        // ====================================================================

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

        fun model(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
                category = ProtoErrorCategory.ERROR_CATEGORY_MODEL,
                message = message,
                cAbiCode = -116,
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

// ============================================================================
// ProtoErrorCode CLASSIFICATION HELPER (Swift parity: RAErrorCode.isExpected)
// ============================================================================

/**
 * Whether this proto error code represents an expected/routine outcome that
 * SHOULD NOT be logged as an error (e.g. user-initiated cancellation).
 *
 * Mirrors Swift's `RAErrorCode.isExpected` extension — returns true only for
 * `ERROR_CODE_CANCELLED` and `ERROR_CODE_STREAM_CANCELLED`.
 */
val ProtoErrorCode.isExpected: Boolean
    get() =
        when (this) {
            ProtoErrorCode.ERROR_CODE_CANCELLED,
            ProtoErrorCode.ERROR_CODE_STREAM_CANCELLED,
            -> true
            else -> false
        }

// ============================================================================
// SDKException CONVENIENCE EXTENSIONS (Swift parity)
// ============================================================================

/**
 * One-line failure-reason summary suitable for log metadata. Mirrors the
 * Swift `failureReason` property.
 */
private val SDKException.failureReason: String
    get() = "[${this.category.name}] ${this.code.name}"

/**
 * Log this exception to the central [Logging] service.
 *
 * Mirrors Swift's `SDKException.log(file:line:function:)`. The level is
 * downgraded to [LogLevel.INFO] for [ProtoErrorCode.ERROR_CODE_CANCELLED];
 * all other codes log at [LogLevel.ERROR]. Call sites should typically gate
 * with `!code.isExpected` (the [SDKException.Companion.make] factory does
 * this automatically).
 *
 * @param file     Source file (default empty — pass via call-site if available).
 * @param line     Source line (default 0).
 * @param function Source function (default empty).
 */
fun SDKException.log(
    file: String = "",
    line: Int = 0,
    function: String = "",
) {
    val level: LogLevel = if (this.code == ProtoErrorCode.ERROR_CODE_CANCELLED) LogLevel.INFO else LogLevel.ERROR
    val fileName = file.substringAfterLast('/')

    val metadata =
        buildMap<String, Any?> {
            put("error_code", this@log.code.name)
            put("error_category", this@log.category.name)
            if (fileName.isNotEmpty()) put("source_file", fileName)
            if (line > 0) put("source_line", line)
            if (function.isNotEmpty()) put("source_function", function)
            this@log.cause?.let { put("underlying_error", it.toString()) }
            put("failure_reason", this@log.failureReason)
        }

    Logging.log(
        level = level,
        category = this.category.name,
        message = this.message ?: this.code.name,
        metadata = metadata,
        file = if (fileName.isNotEmpty()) fileName else null,
        line = if (line > 0) line else null,
        function = if (function.isNotEmpty()) function else null,
    )
}
