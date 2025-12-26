package com.runanywhere.sdk.foundation

/**
 * SDK error codes with numeric values for structured error handling.
 * Matches iOS ErrorCodes.swift exactly.
 *
 * Error code ranges:
 * - 1000-1099: General errors
 * - 1100-1199: Model errors
 * - 1200-1299: Network errors
 * - 1300-1399: Storage errors
 * - 1500-1599: Hardware errors
 * - 1600-1699: Authentication errors
 * - 1700-1799: Generation errors
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/ErrorTypes/ErrorCodes.swift
 */
enum class ErrorCode(
    val code: Int,
) {
    // General errors (1000-1099)
    UNKNOWN(1000),
    INVALID_INPUT(1001),
    NOT_INITIALIZED(1002),
    ALREADY_INITIALIZED(1003),
    OPERATION_CANCELLED(1004),

    // Model errors (1100-1199)
    MODEL_NOT_FOUND(1100),
    MODEL_LOAD_FAILED(1101),
    MODEL_VALIDATION_FAILED(1102),
    MODEL_FORMAT_UNSUPPORTED(1103),
    MODEL_CORRUPTED(1104),
    MODEL_INCOMPATIBLE(1105),

    // Network errors (1200-1299)
    NETWORK_UNAVAILABLE(1200),
    NETWORK_TIMEOUT(1201),
    DOWNLOAD_FAILED(1202),
    UPLOAD_FAILED(1203),
    API_ERROR(1204),

    // Storage errors (1300-1399)
    INSUFFICIENT_STORAGE(1300),
    STORAGE_FULL(1301),
    FILE_NOT_FOUND(1302),
    FILE_ACCESS_DENIED(1303),
    FILE_CORRUPTED(1304),

    // Hardware errors (1500-1599)
    HARDWARE_UNSUPPORTED(1500),
    HARDWARE_UNAVAILABLE(1501),

    // Authentication errors (1600-1699)
    AUTHENTICATION_FAILED(1600),
    AUTHENTICATION_EXPIRED(1601),
    AUTHORIZATION_DENIED(1602),
    API_KEY_INVALID(1603),

    // Generation errors (1700-1799)
    GENERATION_FAILED(1700),
    GENERATION_TIMEOUT(1701),
    TOKEN_LIMIT_EXCEEDED(1702),
    COST_LIMIT_EXCEEDED(1703),
    CONTEXT_TOO_LONG(1704),
    ;

    /**
     * Get user-friendly error message for this error code.
     * Matches iOS ErrorCode.message exactly.
     */
    val message: String
        get() =
            when (this) {
                UNKNOWN -> "An unknown error occurred"
                INVALID_INPUT -> "Invalid input provided"
                NOT_INITIALIZED -> "SDK not initialized"
                ALREADY_INITIALIZED -> "SDK already initialized"
                OPERATION_CANCELLED -> "Operation was cancelled"

                MODEL_NOT_FOUND -> "Model not found"
                MODEL_LOAD_FAILED -> "Failed to load model"
                MODEL_VALIDATION_FAILED -> "Model validation failed"
                MODEL_FORMAT_UNSUPPORTED -> "Model format not supported"
                MODEL_CORRUPTED -> "Model file is corrupted"
                MODEL_INCOMPATIBLE -> "Model incompatible with device"

                NETWORK_UNAVAILABLE -> "Network unavailable"
                NETWORK_TIMEOUT -> "Network request timed out"
                DOWNLOAD_FAILED -> "Download failed"
                UPLOAD_FAILED -> "Upload failed"
                API_ERROR -> "API request failed"

                INSUFFICIENT_STORAGE -> "Insufficient storage space"
                STORAGE_FULL -> "Storage is full"
                FILE_NOT_FOUND -> "File not found"
                FILE_ACCESS_DENIED -> "File access denied"
                FILE_CORRUPTED -> "File is corrupted"

                HARDWARE_UNSUPPORTED -> "Hardware not supported"
                HARDWARE_UNAVAILABLE -> "Hardware unavailable"

                AUTHENTICATION_FAILED -> "Authentication failed"
                AUTHENTICATION_EXPIRED -> "Authentication expired"
                AUTHORIZATION_DENIED -> "Authorization denied"
                API_KEY_INVALID -> "Invalid API key"

                GENERATION_FAILED -> "Text generation failed"
                GENERATION_TIMEOUT -> "Generation timed out"
                TOKEN_LIMIT_EXCEEDED -> "Token limit exceeded"
                COST_LIMIT_EXCEEDED -> "Cost limit exceeded"
                CONTEXT_TOO_LONG -> "Context too long"
            }

    companion object {
        /**
         * Get ErrorCode from numeric code value
         */
        fun fromCode(code: Int): ErrorCode? = entries.find { it.code == code }
    }
}

/**
 * Error category for logical grouping and filtering.
 * Matches iOS ErrorCategory exactly.
 */
enum class ErrorCategory {
    INITIALIZATION,
    MODEL,
    GENERATION,
    NETWORK,
    STORAGE,
    MEMORY,
    HARDWARE,
    VALIDATION,
    AUTHENTICATION,
    COMPONENT,
    FRAMEWORK,
    UNKNOWN,
    ;

    companion object {
        /**
         * Get error category from an ErrorCode
         */
        fun from(errorCode: ErrorCode): ErrorCategory =
            when (errorCode) {
                ErrorCode.NOT_INITIALIZED,
                ErrorCode.ALREADY_INITIALIZED,
                -> INITIALIZATION

                ErrorCode.MODEL_NOT_FOUND,
                ErrorCode.MODEL_LOAD_FAILED,
                ErrorCode.MODEL_VALIDATION_FAILED,
                ErrorCode.MODEL_FORMAT_UNSUPPORTED,
                ErrorCode.MODEL_CORRUPTED,
                ErrorCode.MODEL_INCOMPATIBLE,
                -> MODEL

                ErrorCode.GENERATION_FAILED,
                ErrorCode.GENERATION_TIMEOUT,
                ErrorCode.TOKEN_LIMIT_EXCEEDED,
                ErrorCode.COST_LIMIT_EXCEEDED,
                ErrorCode.CONTEXT_TOO_LONG,
                -> GENERATION

                ErrorCode.NETWORK_UNAVAILABLE,
                ErrorCode.NETWORK_TIMEOUT,
                ErrorCode.DOWNLOAD_FAILED,
                ErrorCode.UPLOAD_FAILED,
                ErrorCode.API_ERROR,
                -> NETWORK

                ErrorCode.INSUFFICIENT_STORAGE,
                ErrorCode.STORAGE_FULL,
                ErrorCode.FILE_NOT_FOUND,
                ErrorCode.FILE_ACCESS_DENIED,
                ErrorCode.FILE_CORRUPTED,
                -> STORAGE

                ErrorCode.HARDWARE_UNSUPPORTED,
                ErrorCode.HARDWARE_UNAVAILABLE,
                -> HARDWARE

                ErrorCode.AUTHENTICATION_FAILED,
                ErrorCode.AUTHENTICATION_EXPIRED,
                ErrorCode.AUTHORIZATION_DENIED,
                ErrorCode.API_KEY_INVALID,
                -> AUTHENTICATION

                ErrorCode.INVALID_INPUT -> VALIDATION

                ErrorCode.UNKNOWN,
                ErrorCode.OPERATION_CANCELLED,
                -> UNKNOWN
            }
    }
}
