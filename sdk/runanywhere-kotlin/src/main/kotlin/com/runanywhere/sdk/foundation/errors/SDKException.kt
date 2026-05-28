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
         * When [cAbiCode] is `null` (the common case), the `c_abi_code` proto
         * field is auto-computed from [code] per the round-trip contract in
         * `errors.proto:516-518` (`cAbiCode = -code.value` for codes ≤ 899).
         * Callers that already hold the underlying `rac_result_t` value
         * (e.g. JNI bridge surfaces) may pass it explicitly to preserve the
         * lossless C ABI round-trip; that value should agree with the
         * negation of [code] per the same contract.
         *
         * @param code     The proto error code (positive magnitude of C ABI code).
         * @param message  Human-readable, non-localized error message.
         * @param category Coarse routing bucket. Defaults to
         *                 [ProtoErrorCategory.ERROR_CATEGORY_COMPONENT].
         * @param cAbiCode Optional explicit `rac_result_t` override. Null →
         *                 auto-compute via the round-trip contract.
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
            val ex = of(code = code, category = category, message = message, cAbiCodeOverride = cAbiCode, cause = cause)
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
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = "$component is not initialized",
                cause = cause,
            )

        fun invalidConfiguration(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_CONFIGURATION,
                category = ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
                message = message,
                cause = cause,
            )

        fun invalidApiKey(cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_API_KEY,
                category = ProtoErrorCategory.ERROR_CATEGORY_AUTH,
                message = "Invalid API key",
                cause = cause,
            )

        fun invalidArgument(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_INVALID_ARGUMENT,
                category = ProtoErrorCategory.ERROR_CATEGORY_VALIDATION,
                message = message,
                cause = cause,
            )

        fun validationFailed(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_VALIDATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_VALIDATION,
                message = message,
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
            val code = ProtoErrorCode.ERROR_CODE_INVALID_ARGUMENT
            val ex =
                SDKException(
                    error =
                        ProtoSDKError(
                            code = code,
                            category = ProtoErrorCategory.ERROR_CATEGORY_VALIDATION,
                            message = message,
                            context =
                                ProtoErrorContext(
                                    metadata = mapOf("field_path" to fieldPath),
                                ),
                            c_abi_code = roundTripCAbiCode(code),
                            nested_message = cause?.message,
                        ),
                    cause = cause,
                )
            if (!code.isExpected) {
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
                cause = cause,
            )

        fun modelNotLoaded(modelId: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
                category = ProtoErrorCategory.ERROR_CATEGORY_MODEL,
                message = if (modelId != null) "Model not loaded: $modelId" else "No model is loaded",
                cause = cause,
            )

        fun modelLoadFailed(modelId: String, reason: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_MODEL,
                message = if (reason != null) "Failed to load model $modelId: $reason" else "Failed to load model: $modelId",
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
                cause = cause,
            )

        /** Swift parity: SDKException.timeout(_:) — NETWORK-bucketed timeout. */
        fun timeout(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_TIMEOUT,
                category = ProtoErrorCategory.ERROR_CATEGORY_NETWORK,
                message = message,
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
                cause = cause,
            )

        fun authenticationFailed(reason: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_AUTHENTICATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_AUTH,
                message = if (reason != null) "Authentication failed: $reason" else "Authentication failed",
                cause = cause,
            )

        fun unauthorized(resource: String? = null, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_UNAUTHORIZED,
                category = ProtoErrorCategory.ERROR_CATEGORY_AUTH,
                message = if (resource != null) "Unauthorized access to: $resource" else "Unauthorized access",
                cause = cause,
            )

        fun notImplemented(feature: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_NOT_IMPLEMENTED,
                category = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
                message = "Not implemented: $feature",
                cause = cause,
            )

        /**
         * Swift parity: `SDKException.cancelled(_:)` — INTERNAL-bucketed
         * user-initiated cancellation. `shouldLog=false` because
         * `ERROR_CODE_CANCELLED` is classified as expected
         * (see [ProtoErrorCode.isExpected]).
         */
        fun cancelled(message: String = "Operation cancelled", cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_CANCELLED,
                category = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
                message = message,
                cause = cause,
            )

        // ====================================================================
        // MODALITY FACTORIES (STT/TTS/LLM/VAD/VLM/VoiceAgent)
        //
        // Per errors.proto:516-518, `c_abi_code` MUST equal `-int32(code)` for
        // codes ≤ 899. The chosen ProtoErrorCode determines the cAbiCode via
        // the of() helper's automatic round-trip computation — no hand-written
        // cAbiCode literals.
        // ====================================================================

        fun tts(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cause = cause,
            )

        fun vlm(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_PROCESSING_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cause = cause,
            )

        fun voiceAgent(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
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
                cause = cause,
            )

        fun platform(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_ADAPTER_NOT_SET,
                category = ProtoErrorCategory.ERROR_CATEGORY_CONFIGURATION,
                message = message,
                cause = cause,
            )

        fun model(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
                category = ProtoErrorCategory.ERROR_CATEGORY_MODEL,
                message = message,
                cause = cause,
            )

        fun operation(message: String, cause: Throwable? = null) =
            of(
                code = ProtoErrorCode.ERROR_CODE_GENERATION_FAILED,
                category = ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
                message = message,
                cause = cause,
            )

        // ====================================================================
        // ERROR CONVERSION (Swift parity: SDKException.from / fromONNXCode)
        // ====================================================================

        /**
         * Convert any [Throwable] into an SDKException. If [error] is already
         * an SDKException, returns it unchanged. A null [error] becomes an
         * `ERROR_CODE_UNKNOWN` envelope tagged with [category] and the message
         * `"Unknown error"`. Otherwise wraps in an `ERROR_CODE_UNKNOWN`
         * envelope tagged with [category] and the underlying throwable's
         * message.
         *
         * Mirrors Swift's `SDKException.from(_:category:)` (SDKException.swift:250-270).
         * The two Swift overloads (non-null and nullable) collapse into a
         * single nullable Kotlin signature because they share a JVM
         * descriptor. The Swift implementation additionally maps
         * `NSURLErrorDomain` codes — Kotlin defers that to platform-specific
         * HTTP adapters (e.g. [com.runanywhere.sdk.foundation.bridge.HTTPClientAdapter]).
         */
        fun from(
            error: Throwable?,
            category: ProtoErrorCategory = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL,
        ): SDKException {
            if (error == null) {
                return make(
                    code = ProtoErrorCode.ERROR_CODE_UNKNOWN,
                    message = "Unknown error",
                    category = category,
                )
            }
            if (error is SDKException) return error
            return make(
                code = ProtoErrorCode.ERROR_CODE_UNKNOWN,
                message = error.message ?: error.toString(),
                category = category,
                cause = error,
            )
        }

        /**
         * Map an ONNX Runtime C error code into an SDKException.
         * Mirrors Swift's `SDKException.fromONNXCode(_:)` at SDKException.swift:299-341.
         */
        fun fromONNXCode(code: Int): SDKException {
            val (raCode, message) =
                when (code) {
                    0 -> ProtoErrorCode.ERROR_CODE_UNKNOWN to "Unexpected success code passed to error handler"
                    -1 -> ProtoErrorCode.ERROR_CODE_INITIALIZATION_FAILED to "ONNX Runtime initialization failed"
                    -2 -> ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED to "Failed to load ONNX model"
                    -3 -> ProtoErrorCode.ERROR_CODE_GENERATION_FAILED to "ONNX inference failed"
                    -4 -> ProtoErrorCode.ERROR_CODE_INVALID_STATE to "Invalid ONNX handle"
                    -5 -> ProtoErrorCode.ERROR_CODE_INVALID_INPUT to "Invalid ONNX parameters"
                    -6 -> ProtoErrorCode.ERROR_CODE_INSUFFICIENT_MEMORY to "ONNX Runtime out of memory"
                    -7 -> ProtoErrorCode.ERROR_CODE_NOT_IMPLEMENTED to "ONNX feature not implemented"
                    -8 -> ProtoErrorCode.ERROR_CODE_CANCELLED to "ONNX operation cancelled"
                    -9 -> ProtoErrorCode.ERROR_CODE_TIMEOUT to "ONNX operation timed out"
                    -10 -> ProtoErrorCode.ERROR_CODE_STORAGE_ERROR to "ONNX IO error"
                    else -> ProtoErrorCode.ERROR_CODE_UNKNOWN to "ONNX error code: $code"
                }
            return make(code = raCode, message = message, category = ProtoErrorCategory.ERROR_CATEGORY_INTERNAL)
        }

        /**
         * Compute the round-trip `c_abi_code` for a proto [code] per the
         * errors.proto contract (lines 516-518): for codes in `1..899`, the
         * cAbiCode MUST equal `-code.value`; for Web-only WASM codes (≥ 900)
         * there is no canonical C ABI value, so cAbiCode is unset.
         *
         * Mirrors Swift's init at SDKException.swift:48-51.
         */
        private fun roundTripCAbiCode(code: ProtoErrorCode): Int? {
            val raw = code.value
            return if (raw in 1..899) -raw else null
        }

        /**
         * Internal helper to construct an SDKException with all fields set.
         * The `c_abi_code` defaults to [roundTripCAbiCode] of [code] per the
         * proto's round-trip contract; pass [cAbiCodeOverride] only when the
         * caller already holds the underlying `rac_result_t` value (e.g. JNI
         * bridge surfaces returning a concrete failure code).
         */
        private fun of(
            code: ProtoErrorCode,
            category: ProtoErrorCategory,
            message: String,
            cAbiCodeOverride: Int? = null,
            cause: Throwable? = null,
        ): SDKException =
            SDKException(
                error =
                    ProtoSDKError(
                        code = code,
                        category = category,
                        message = message,
                        c_abi_code = cAbiCodeOverride ?: roundTripCAbiCode(code),
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
