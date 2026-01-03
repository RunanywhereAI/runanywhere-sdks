/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Mapping utilities for C++ runanywhere-commons error codes to Kotlin SDKError.
 * Provides type-safe conversion between C++ raw error codes and Kotlin error types.
 */

package com.runanywhere.sdk.foundation.errors

/**
 * C++ runanywhere-commons error code constants.
 *
 * These constants match the RAC_* error codes from the runanywhere-commons C API.
 * Used for mapping between C++ return values and Kotlin error types.
 */
object CommonsErrorCode {
    /** Operation completed successfully */
    const val RAC_SUCCESS = 0

    /** Generic error */
    const val RAC_ERROR = -1

    /** Invalid argument provided */
    const val RAC_ERROR_INVALID_ARGUMENT = -2

    /** Library not initialized */
    const val RAC_ERROR_NOT_INITIALIZED = -3

    /** Already initialized */
    const val RAC_ERROR_ALREADY_INITIALIZED = -4

    /** Out of memory */
    const val RAC_ERROR_OUT_OF_MEMORY = -5

    /** File not found */
    const val RAC_ERROR_FILE_NOT_FOUND = -6

    /** Operation timed out */
    const val RAC_ERROR_TIMEOUT = -7

    /** Operation was cancelled */
    const val RAC_ERROR_CANCELLED = -8

    /** Network error */
    const val RAC_ERROR_NETWORK = -9

    /** Model not loaded */
    const val RAC_ERROR_MODEL_NOT_LOADED = -10

    /** Model load failed */
    const val RAC_ERROR_MODEL_LOAD_FAILED = -11

    /** Platform adapter not set */
    const val RAC_ERROR_PLATFORM_ADAPTER_NOT_SET = -12

    /** Invalid handle */
    const val RAC_ERROR_INVALID_HANDLE = -13

    // Component-specific errors
    /** STT transcription failed */
    const val RAC_ERROR_STT_TRANSCRIPTION_FAILED = -100

    /** TTS synthesis failed */
    const val RAC_ERROR_TTS_SYNTHESIS_FAILED = -101

    /** LLM generation failed */
    const val RAC_ERROR_LLM_GENERATION_FAILED = -102

    /** VAD detection failed */
    const val RAC_ERROR_VAD_DETECTION_FAILED = -103

    /** Voice agent error */
    const val RAC_ERROR_VOICE_AGENT = -104

    // Download errors
    /** Download failed */
    const val RAC_ERROR_DOWNLOAD_FAILED = -200

    /** Download cancelled */
    const val RAC_ERROR_DOWNLOAD_CANCELLED = -201

    /** Insufficient storage */
    const val RAC_ERROR_INSUFFICIENT_STORAGE = -202

    // Authentication errors
    /** Authentication failed */
    const val RAC_ERROR_AUTHENTICATION_FAILED = -300

    /** Invalid API key */
    const val RAC_ERROR_INVALID_API_KEY = -301

    /** Unauthorized */
    const val RAC_ERROR_UNAUTHORIZED = -302

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

/**
 * Mapping utilities for converting C++ error codes to Kotlin SDKError instances.
 *
 * This object provides functions for:
 * - Converting raw C++ error codes to SDKError
 * - Wrapping C++ function results in Kotlin Result types
 * - Providing contextual error messages for C++ operations
 *
 * Usage:
 * ```kotlin
 * // Convert a C++ error code to SDKError
 * val error = CommonsErrorMapping.toSDKError(errorCode, "Failed to load model")
 *
 * // Check and throw if error
 * CommonsErrorMapping.checkSuccess(result, "rac_init")
 *
 * // Wrap in Result
 * val result = CommonsErrorMapping.toResult(nativeResult, operation = "model loading")
 * ```
 */
object CommonsErrorMapping {

    /**
     * Convert a C++ error code to the corresponding Kotlin ErrorCode enum.
     *
     * @param rawValue The C++ error code (RAC_* constant)
     * @return The corresponding Kotlin ErrorCode enum value
     */
    fun toErrorCode(rawValue: Int): ErrorCode {
        return when (rawValue) {
            CommonsErrorCode.RAC_SUCCESS -> ErrorCode.SUCCESS
            CommonsErrorCode.RAC_ERROR -> ErrorCode.UNKNOWN
            CommonsErrorCode.RAC_ERROR_INVALID_ARGUMENT -> ErrorCode.INVALID_ARGUMENT
            CommonsErrorCode.RAC_ERROR_NOT_INITIALIZED -> ErrorCode.NOT_INITIALIZED
            CommonsErrorCode.RAC_ERROR_ALREADY_INITIALIZED -> ErrorCode.ALREADY_INITIALIZED
            CommonsErrorCode.RAC_ERROR_OUT_OF_MEMORY -> ErrorCode.OUT_OF_MEMORY
            CommonsErrorCode.RAC_ERROR_FILE_NOT_FOUND -> ErrorCode.FILE_NOT_FOUND
            CommonsErrorCode.RAC_ERROR_TIMEOUT -> ErrorCode.TIMEOUT
            CommonsErrorCode.RAC_ERROR_CANCELLED -> ErrorCode.CANCELLED
            CommonsErrorCode.RAC_ERROR_NETWORK -> ErrorCode.NETWORK_ERROR
            CommonsErrorCode.RAC_ERROR_MODEL_NOT_LOADED -> ErrorCode.MODEL_NOT_LOADED
            CommonsErrorCode.RAC_ERROR_MODEL_LOAD_FAILED -> ErrorCode.MODEL_LOAD_FAILED
            CommonsErrorCode.RAC_ERROR_PLATFORM_ADAPTER_NOT_SET -> ErrorCode.PLATFORM_ADAPTER_NOT_SET
            CommonsErrorCode.RAC_ERROR_INVALID_HANDLE -> ErrorCode.INVALID_HANDLE
            CommonsErrorCode.RAC_ERROR_STT_TRANSCRIPTION_FAILED -> ErrorCode.STT_TRANSCRIPTION_FAILED
            CommonsErrorCode.RAC_ERROR_TTS_SYNTHESIS_FAILED -> ErrorCode.TTS_SYNTHESIS_FAILED
            CommonsErrorCode.RAC_ERROR_LLM_GENERATION_FAILED -> ErrorCode.LLM_GENERATION_FAILED
            CommonsErrorCode.RAC_ERROR_VAD_DETECTION_FAILED -> ErrorCode.VAD_DETECTION_FAILED
            CommonsErrorCode.RAC_ERROR_VOICE_AGENT -> ErrorCode.VOICE_AGENT_ERROR
            CommonsErrorCode.RAC_ERROR_DOWNLOAD_FAILED -> ErrorCode.DOWNLOAD_FAILED
            CommonsErrorCode.RAC_ERROR_DOWNLOAD_CANCELLED -> ErrorCode.DOWNLOAD_CANCELLED
            CommonsErrorCode.RAC_ERROR_INSUFFICIENT_STORAGE -> ErrorCode.INSUFFICIENT_STORAGE
            CommonsErrorCode.RAC_ERROR_AUTHENTICATION_FAILED -> ErrorCode.AUTHENTICATION_FAILED
            CommonsErrorCode.RAC_ERROR_INVALID_API_KEY -> ErrorCode.INVALID_API_KEY
            CommonsErrorCode.RAC_ERROR_UNAUTHORIZED -> ErrorCode.UNAUTHORIZED
            else -> ErrorCode.fromRawValue(rawValue)
        }
    }

    /**
     * Convert a C++ error code to an SDKError instance.
     *
     * @param rawValue The C++ error code (RAC_* constant)
     * @param message Optional custom error message (uses default if not provided)
     * @param cause Optional underlying throwable cause
     * @return An SDKError representing the C++ error
     */
    fun toSDKError(
        rawValue: Int,
        message: String? = null,
        cause: Throwable? = null
    ): SDKError {
        val errorCode = toErrorCode(rawValue)
        val errorCategory = ErrorCategory.fromErrorCode(errorCode)
        val errorMessage = message ?: errorCode.description
        return SDKError(
            code = errorCode,
            category = errorCategory,
            message = errorMessage,
            cause = cause
        )
    }

    /**
     * Convert a C++ error code to an SDKError with operation context.
     *
     * @param rawValue The C++ error code (RAC_* constant)
     * @param operation The name of the operation that failed
     * @param details Optional additional details about the failure
     * @param cause Optional underlying throwable cause
     * @return An SDKError with contextual message about the failed operation
     */
    fun toSDKErrorWithContext(
        rawValue: Int,
        operation: String,
        details: String? = null,
        cause: Throwable? = null
    ): SDKError {
        val errorCode = toErrorCode(rawValue)
        val errorCategory = ErrorCategory.fromErrorCode(errorCode)

        val message = buildString {
            append("$operation failed")
            if (details != null) {
                append(": $details")
            }
            append(" (error code: $rawValue - ${errorCode.description})")
        }

        return SDKError(
            code = errorCode,
            category = errorCategory,
            message = message,
            cause = cause
        )
    }

    /**
     * Check if a C++ return code indicates success.
     *
     * @param rawValue The C++ return code
     * @return true if the code indicates success
     */
    fun isSuccess(rawValue: Int): Boolean = CommonsErrorCode.isSuccess(rawValue)

    /**
     * Check if a C++ return code indicates an error.
     *
     * @param rawValue The C++ return code
     * @return true if the code indicates an error
     */
    fun isError(rawValue: Int): Boolean = CommonsErrorCode.isError(rawValue)

    /**
     * Check a C++ return code and throw an SDKError if it indicates failure.
     *
     * @param rawValue The C++ return code to check
     * @param operation The name of the operation (for error message)
     * @throws SDKError if the return code indicates failure
     */
    fun checkSuccess(rawValue: Int, operation: String) {
        if (isError(rawValue)) {
            throw toSDKErrorWithContext(rawValue, operation)
        }
    }

    /**
     * Check a C++ return code and throw an SDKError if it indicates failure.
     *
     * @param rawValue The C++ return code to check
     * @param operation The name of the operation (for error message)
     * @param details Additional details to include in the error message
     * @throws SDKError if the return code indicates failure
     */
    fun checkSuccess(rawValue: Int, operation: String, details: String) {
        if (isError(rawValue)) {
            throw toSDKErrorWithContext(rawValue, operation, details)
        }
    }

    /**
     * Convert a C++ function result to a Kotlin Result.
     *
     * For functions that only return an error code (no payload), this wraps
     * the result in a Result<Unit>.
     *
     * @param rawValue The C++ return code
     * @param operation The name of the operation (for error message)
     * @return Result<Unit> - success if code is 0 or positive, failure otherwise
     */
    fun toResult(rawValue: Int, operation: String): Result<Unit> {
        return if (isSuccess(rawValue)) {
            Result.success(Unit)
        } else {
            Result.failure(toSDKErrorWithContext(rawValue, operation))
        }
    }

    /**
     * Convert a C++ function result to a Kotlin Result with a value.
     *
     * For functions that return a value on success, this wraps the result
     * appropriately. The value is only used if the error code indicates success.
     *
     * @param rawValue The C++ return code
     * @param value The value to return on success
     * @param operation The name of the operation (for error message)
     * @return Result<T> - success with value if code is 0 or positive, failure otherwise
     */
    fun <T> toResult(rawValue: Int, value: T, operation: String): Result<T> {
        return if (isSuccess(rawValue)) {
            Result.success(value)
        } else {
            Result.failure(toSDKErrorWithContext(rawValue, operation))
        }
    }

    /**
     * Convert a nullable value with error code to a Result.
     *
     * This is useful when the C++ function returns null on error along with
     * an error code out-parameter.
     *
     * @param value The nullable value returned by the C++ function
     * @param errorCode The error code (used if value is null)
     * @param operation The name of the operation (for error message)
     * @return Result<T> - success with non-null value, or failure
     */
    fun <T : Any> toResultFromNullable(
        value: T?,
        errorCode: Int,
        operation: String
    ): Result<T> {
        return if (value != null) {
            Result.success(value)
        } else {
            val code = if (isError(errorCode)) errorCode else CommonsErrorCode.RAC_ERROR
            Result.failure(toSDKErrorWithContext(code, operation))
        }
    }

    /**
     * Get a descriptive error message for a C++ error code.
     *
     * @param rawValue The C++ error code
     * @return A human-readable description of the error
     */
    fun getErrorDescription(rawValue: Int): String {
        val errorCode = toErrorCode(rawValue)
        return errorCode.description
    }

    /**
     * Get the error category for a C++ error code.
     *
     * @param rawValue The C++ error code
     * @return The error category
     */
    fun getErrorCategory(rawValue: Int): ErrorCategory {
        val errorCode = toErrorCode(rawValue)
        return ErrorCategory.fromErrorCode(errorCode)
    }
}

// ============================================================================
// EXTENSION FUNCTIONS FOR CONVENIENT ERROR HANDLING
// ============================================================================

/**
 * Convert a C++ raw error code to an SDKError.
 *
 * Extension function for convenient error conversion.
 *
 * @param message Optional custom error message
 * @param cause Optional underlying throwable cause
 * @return An SDKError representing this error code
 */
fun Int.toSDKError(message: String? = null, cause: Throwable? = null): SDKError {
    return CommonsErrorMapping.toSDKError(this, message, cause)
}

/**
 * Convert a C++ raw error code to a Kotlin ErrorCode enum.
 *
 * @return The corresponding Kotlin ErrorCode enum value
 */
fun Int.toErrorCode(): ErrorCode {
    return CommonsErrorMapping.toErrorCode(this)
}

/**
 * Check if this C++ raw error code indicates success.
 *
 * @return true if this code indicates success (>= 0)
 */
fun Int.isCommonsSuccess(): Boolean {
    return CommonsErrorMapping.isSuccess(this)
}

/**
 * Check if this C++ raw error code indicates failure.
 *
 * @return true if this code indicates failure (< 0)
 */
fun Int.isCommonsError(): Boolean {
    return CommonsErrorMapping.isError(this)
}

/**
 * Throw an SDKError if this C++ raw error code indicates failure.
 *
 * @param operation The name of the operation (for error message)
 * @throws SDKError if this code indicates failure
 */
fun Int.throwIfError(operation: String) {
    CommonsErrorMapping.checkSuccess(this, operation)
}

/**
 * Convert this C++ raw error code to a Kotlin Result.
 *
 * @param operation The name of the operation (for error message)
 * @return Result<Unit> - success if code >= 0, failure otherwise
 */
fun Int.toCommonsResult(operation: String): Result<Unit> {
    return CommonsErrorMapping.toResult(this, operation)
}

/**
 * Convert this C++ raw error code to a Kotlin Result with a value.
 *
 * @param value The value to return on success
 * @param operation The name of the operation (for error message)
 * @return Result<T> - success with value if code >= 0, failure otherwise
 */
fun <T> Int.toCommonsResult(value: T, operation: String): Result<T> {
    return CommonsErrorMapping.toResult(this, value, operation)
}
