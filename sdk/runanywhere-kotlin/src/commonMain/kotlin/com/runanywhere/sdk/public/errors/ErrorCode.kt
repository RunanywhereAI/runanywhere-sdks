package com.runanywhere.sdk.public.errors

/**
 * SDK error codes for machine-readable identification.
 *
 * Aligned with iOS: `RunAnywhere/Foundation/ErrorTypes/ErrorCodes.swift`
 */
enum class ErrorCode(val code: Int, val message: String) {
    // General errors (1000-1099)
    UNKNOWN(1000, "An unknown error occurred"),
    INVALID_INPUT(1001, "Invalid input provided"),
    NOT_INITIALIZED(1002, "SDK not initialized"),
    ALREADY_INITIALIZED(1003, "SDK already initialized"),
    OPERATION_CANCELLED(1004, "Operation was cancelled"),

    // Model errors (1100-1199)
    MODEL_NOT_FOUND(1100, "Model not found"),
    MODEL_LOAD_FAILED(1101, "Failed to load model"),
    MODEL_VALIDATION_FAILED(1102, "Model validation failed"),
    MODEL_FORMAT_UNSUPPORTED(1103, "Model format not supported"),
    MODEL_CORRUPTED(1104, "Model file is corrupted"),
    MODEL_INCOMPATIBLE(1105, "Model incompatible with device"),

    // Network errors (1200-1299)
    NETWORK_UNAVAILABLE(1200, "Network unavailable"),
    NETWORK_TIMEOUT(1201, "Network request timed out"),
    DOWNLOAD_FAILED(1202, "Download failed"),
    UPLOAD_FAILED(1203, "Upload failed"),
    API_ERROR(1204, "API request failed"),

    // Storage errors (1300-1399)
    INSUFFICIENT_STORAGE(1300, "Insufficient storage space"),
    STORAGE_FULL(1301, "Storage is full"),
    FILE_NOT_FOUND(1302, "File not found"),
    FILE_ACCESS_DENIED(1303, "File access denied"),
    FILE_CORRUPTED(1304, "File is corrupted"),

    // Hardware errors (1500-1599)
    HARDWARE_UNSUPPORTED(1500, "Hardware not supported"),
    HARDWARE_UNAVAILABLE(1501, "Hardware unavailable"),

    // Authentication errors (1600-1699)
    AUTHENTICATION_FAILED(1600, "Authentication failed"),
    AUTHENTICATION_EXPIRED(1601, "Authentication expired"),
    AUTHORIZATION_DENIED(1602, "Authorization denied"),
    API_KEY_INVALID(1603, "Invalid API key"),

    // Generation errors (1700-1799)
    GENERATION_FAILED(1700, "Text generation failed"),
    GENERATION_TIMEOUT(1701, "Generation timed out"),
    TOKEN_LIMIT_EXCEEDED(1702, "Token limit exceeded"),
    COST_LIMIT_EXCEEDED(1703, "Cost limit exceeded"),
    CONTEXT_TOO_LONG(1704, "Context too long")
}
