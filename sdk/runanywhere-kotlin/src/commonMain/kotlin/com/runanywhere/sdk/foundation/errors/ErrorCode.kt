/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Error code enum matching iOS ErrorCode for cross-platform consistency.
 */

package com.runanywhere.sdk.foundation.errors

/**
 * Error codes for SDK operations.
 *
 * This enum matches the iOS SDK's ErrorCode for cross-platform consistency.
 * Each error code has a corresponding C++ raw value for interop with
 * the runanywhere-commons C++ library.
 *
 * @property rawValue The C++ compatible error code value for interop.
 */
enum class ErrorCode(
    val rawValue: Int,
) {
    // ========================================================================
    // SUCCESS
    // ========================================================================

    /**
     * Operation completed successfully.
     */
    SUCCESS(0),

    // ========================================================================
    // GENERAL ERRORS
    // ========================================================================

    /**
     * Unknown or unspecified error.
     */
    UNKNOWN(-1),

    /**
     * Invalid argument provided to a function.
     */
    INVALID_ARGUMENT(-2),

    /**
     * SDK or component has not been initialized.
     */
    NOT_INITIALIZED(-3),

    /**
     * SDK or component has already been initialized.
     */
    ALREADY_INITIALIZED(-4),

    /**
     * Out of memory error.
     */
    OUT_OF_MEMORY(-5),

    // ========================================================================
    // FILE AND RESOURCE ERRORS
    // ========================================================================

    /**
     * File not found at the specified path.
     */
    FILE_NOT_FOUND(-6),

    /**
     * Model not found in registry or at path.
     */
    MODEL_NOT_FOUND(-6),

    // ========================================================================
    // OPERATION ERRORS
    // ========================================================================

    /**
     * Operation timed out.
     */
    TIMEOUT(-7),

    /**
     * Operation was cancelled by the user or system.
     */
    CANCELLED(-8),

    // ========================================================================
    // NETWORK ERRORS
    // ========================================================================

    /**
     * Network is unavailable or network operation failed.
     */
    NETWORK_UNAVAILABLE(-9),

    /**
     * Network error during operation.
     */
    NETWORK_ERROR(-9),

    // ========================================================================
    // MODEL ERRORS
    // ========================================================================

    /**
     * Model is not loaded and operation requires a loaded model.
     */
    MODEL_NOT_LOADED(-10),

    /**
     * Failed to load the model.
     */
    MODEL_LOAD_FAILED(-11),

    // ========================================================================
    // PLATFORM ERRORS
    // ========================================================================

    /**
     * Platform adapter has not been set before initialization.
     */
    PLATFORM_ADAPTER_NOT_SET(-12),

    /**
     * Invalid handle provided to a function.
     */
    INVALID_HANDLE(-13),

    // ========================================================================
    // COMPONENT-SPECIFIC ERRORS
    // ========================================================================

    /**
     * Speech-to-text transcription failed.
     */
    STT_TRANSCRIPTION_FAILED(-100),

    /**
     * Text-to-speech synthesis failed.
     */
    TTS_SYNTHESIS_FAILED(-101),

    /**
     * LLM generation failed.
     */
    LLM_GENERATION_FAILED(-102),

    /**
     * Voice activity detection failed.
     */
    VAD_DETECTION_FAILED(-103),

    /**
     * Voice agent pipeline error.
     */
    VOICE_AGENT_ERROR(-104),

    /**
     * Diffusion image generation failed.
     */
    DIFFUSION_GENERATION_FAILED(-105),

    // ========================================================================
    // DOWNLOAD ERRORS
    // ========================================================================

    /**
     * Download failed.
     */
    DOWNLOAD_FAILED(-200),

    /**
     * Download was cancelled.
     */
    DOWNLOAD_CANCELLED(-201),

    /**
     * Insufficient storage space for download.
     */
    INSUFFICIENT_STORAGE(-202),

    // ========================================================================
    // AUTHENTICATION ERRORS
    // ========================================================================

    /**
     * Authentication failed or required.
     */
    AUTHENTICATION_FAILED(-300),

    /**
     * API key is invalid.
     */
    INVALID_API_KEY(-301),

    /**
     * Access denied or unauthorized.
     */
    UNAUTHORIZED(-302),
    ;

    companion object {
        /**
         * Get the ErrorCode from a C++ raw value.
         *
         * @param rawValue The C++ error code value
         * @return The corresponding ErrorCode, or UNKNOWN if not found
         */
        fun fromRawValue(rawValue: Int): ErrorCode {
            return entries.find { it.rawValue == rawValue } ?: UNKNOWN
        }

        /**
         * Check if a raw value indicates success.
         *
         * @param rawValue The C++ error code value
         * @return true if the value indicates success (>= 0)
         */
        fun isSuccess(rawValue: Int): Boolean = rawValue >= 0

        /**
         * Check if a raw value indicates an error.
         *
         * @param rawValue The C++ error code value
         * @return true if the value indicates an error (< 0)
         */
        fun isError(rawValue: Int): Boolean = rawValue < 0
    }

    /**
     * Check if this error code represents success.
     */
    val isSuccess: Boolean
        get() = this == SUCCESS

    /**
     * Check if this error code represents an error.
     */
    val isError: Boolean
        get() = this != SUCCESS

    /**
     * Get a human-readable description of the error.
     */
    val description: String
        get() =
            when (this) {
                SUCCESS -> "Operation completed successfully"
                UNKNOWN -> "An unknown error occurred"
                INVALID_ARGUMENT -> "Invalid argument provided"
                NOT_INITIALIZED -> "SDK or component not initialized"
                ALREADY_INITIALIZED -> "SDK or component already initialized"
                OUT_OF_MEMORY -> "Out of memory"
                FILE_NOT_FOUND -> "File not found"
                MODEL_NOT_FOUND -> "Model not found"
                TIMEOUT -> "Operation timed out"
                CANCELLED -> "Operation was cancelled"
                NETWORK_UNAVAILABLE -> "Network is unavailable"
                NETWORK_ERROR -> "Network error occurred"
                MODEL_NOT_LOADED -> "Model not loaded"
                MODEL_LOAD_FAILED -> "Failed to load model"
                PLATFORM_ADAPTER_NOT_SET -> "Platform adapter not set"
                INVALID_HANDLE -> "Invalid handle"
                STT_TRANSCRIPTION_FAILED -> "Speech-to-text transcription failed"
                TTS_SYNTHESIS_FAILED -> "Text-to-speech synthesis failed"
                LLM_GENERATION_FAILED -> "LLM generation failed"
                VAD_DETECTION_FAILED -> "Voice activity detection failed"
                VOICE_AGENT_ERROR -> "Voice agent error"
                DIFFUSION_GENERATION_FAILED -> "Image generation failed"
                DOWNLOAD_FAILED -> "Download failed"
                DOWNLOAD_CANCELLED -> "Download cancelled"
                INSUFFICIENT_STORAGE -> "Insufficient storage space"
                AUTHENTICATION_FAILED -> "Authentication failed"
                INVALID_API_KEY -> "Invalid API key"
                UNAUTHORIZED -> "Unauthorized access"
            }
}
