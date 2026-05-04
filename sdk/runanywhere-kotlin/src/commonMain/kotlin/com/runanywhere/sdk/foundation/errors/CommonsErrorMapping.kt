/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Mapping utilities for C++ runanywhere-commons error codes to proto-canonical SDKException.
 *
 * Wave 2 KOTLIN: Legacy SDKError/ErrorCode/ErrorCategory have been DELETED.
 * All conversions go through SDKException, which embeds the proto-canonical
 * SDKError wire payload (with `c_abi_code` for lossless C ABI round-trip).
 */

package com.runanywhere.sdk.foundation.errors

/**
 * Convenience constants for the most common runanywhere-commons error codes.
 *
 * These match the RAC_* error codes from the runanywhere-commons C API.
 * For new code, prefer using the negative `rac_result_t` integer directly
 * with `Int.toSDKException()` / `Int.throwIfCAbiErrorAsException()`.
 */
object CommonsErrorCode {
    /** Operation completed successfully */
    const val RAC_SUCCESS = 0

    /** Generic error */
    const val RAC_ERROR = -1

    /** Invalid argument provided */
    const val RAC_ERROR_INVALID_ARGUMENT = -259

    /** Library not initialized */
    const val RAC_ERROR_NOT_INITIALIZED = -100

    /** Already initialized */
    const val RAC_ERROR_ALREADY_INITIALIZED = -101

    /** Out of memory */
    const val RAC_ERROR_OUT_OF_MEMORY = -221

    /** File not found */
    const val RAC_ERROR_FILE_NOT_FOUND = -183

    /** Operation timed out */
    const val RAC_ERROR_TIMEOUT = -155

    /** Operation was cancelled */
    const val RAC_ERROR_CANCELLED = -380

    /** Network error */
    const val RAC_ERROR_NETWORK = -151

    /** Model not loaded */
    const val RAC_ERROR_MODEL_NOT_LOADED = -116

    /** Model load failed */
    const val RAC_ERROR_MODEL_LOAD_FAILED = -111

    /** Invalid handle */
    const val RAC_ERROR_INVALID_HANDLE = -610

    /** Download failed */
    const val RAC_ERROR_DOWNLOAD_FAILED = -153

    /** Insufficient storage */
    const val RAC_ERROR_INSUFFICIENT_STORAGE = -180

    /** Authentication failed */
    const val RAC_ERROR_AUTHENTICATION_FAILED = -320

    /** Invalid API key */
    const val RAC_ERROR_INVALID_API_KEY = -104

    /** Unauthorized */
    const val RAC_ERROR_UNAUTHORIZED = -321

    /**
     * Check if an error code indicates success.
     *
     * @param code The C++ error code
     * @return true if the code indicates success (>= 0)
     */
    fun isSuccess(code: Int): Boolean = code >= 0

    /**
     * Check if an error code indicates failure.
     *
     * @param code The C++ error code
     * @return true if the code indicates failure (< 0)
     */
    fun isError(code: Int): Boolean = code < 0
}

// ============================================================================
// EXTENSION FUNCTIONS — proto-canonical (Wave 2 KOTLIN)
// ============================================================================

/**
 * Convert this C++ raw error code (rac_result_t) to a proto-canonical
 * [SDKException]. The `c_abi_code` field on the embedded proto SDKError is
 * set to the original negative value, allowing lossless round-trip with
 * the C ABI.
 *
 * @param operation Optional operation name for context in the message
 * @return SDKException wrapping the proto-canonical SDKError payload
 */
fun Int.toSDKException(operation: String? = null, cause: Throwable? = null): SDKException =
    SDKException.fromCAbiCode(this, operation, cause)

/**
 * Throw a proto-canonical [SDKException] if this C++ raw error code
 * indicates failure (< 0).
 *
 * @param operation The name of the operation (for error message)
 * @throws SDKException if this code indicates failure
 */
fun Int.throwIfCAbiErrorAsException(operation: String) {
    if (this < 0) {
        throw SDKException.fromCAbiCode(this, operation)
    }
}

/**
 * Backwards-compatible alias for [throwIfCAbiErrorAsException]. New callers
 * should prefer the explicit name.
 */
fun Int.throwIfError(operation: String) {
    if (this < 0) {
        throw SDKException.fromCAbiCode(this, operation)
    }
}

/**
 * Check if this C++ raw error code indicates success.
 *
 * @return true if this code indicates success (>= 0)
 */
fun Int.isCommonsSuccess(): Boolean = this >= 0

/**
 * Check if this C++ raw error code indicates failure.
 *
 * @return true if this code indicates failure (< 0)
 */
fun Int.isCommonsError(): Boolean = this < 0

/**
 * Convert this C++ raw error code to a Kotlin Result<Unit>.
 *
 * @param operation The name of the operation (for error message)
 * @return Result<Unit> - success if code >= 0, failure otherwise
 */
fun Int.toCommonsResult(operation: String): Result<Unit> {
    return if (this >= 0) {
        Result.success(Unit)
    } else {
        Result.failure(SDKException.fromCAbiCode(this, operation))
    }
}

/**
 * Convert this C++ raw error code to a Kotlin Result<T> with a value.
 *
 * @param value The value to return on success
 * @param operation The name of the operation (for error message)
 * @return Result<T> - success with value if code >= 0, failure otherwise
 */
fun <T> Int.toCommonsResult(value: T, operation: String): Result<T> {
    return if (this >= 0) {
        Result.success(value)
    } else {
        Result.failure(SDKException.fromCAbiCode(this, operation))
    }
}
