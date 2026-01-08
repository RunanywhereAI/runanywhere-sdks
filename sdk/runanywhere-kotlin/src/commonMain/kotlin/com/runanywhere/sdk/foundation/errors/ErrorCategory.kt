/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Error category enum matching iOS ErrorCategory for cross-platform consistency.
 */

package com.runanywhere.sdk.foundation.errors

/**
 * Categories for SDK errors.
 *
 * This enum matches the iOS SDK's ErrorCategory for cross-platform consistency.
 * Error categories provide a high-level grouping of errors, making it easier
 * to handle related errors uniformly.
 *
 * @property description A human-readable description of the error category.
 */
enum class ErrorCategory {
    // ========================================================================
    // GENERAL CATEGORIES
    // ========================================================================

    /**
     * General or unclassified errors.
     */
    GENERAL,

    /**
     * Configuration-related errors.
     */
    CONFIGURATION,

    /**
     * Initialization-related errors.
     */
    INITIALIZATION,

    // ========================================================================
    // RESOURCE CATEGORIES
    // ========================================================================

    /**
     * File and resource access errors.
     */
    FILE_RESOURCE,

    /**
     * Memory and resource allocation errors.
     */
    MEMORY,

    /**
     * Storage-related errors (insufficient space, etc.).
     */
    STORAGE,

    // ========================================================================
    // OPERATION CATEGORIES
    // ========================================================================

    /**
     * Operation lifecycle errors (timeout, cancelled, etc.).
     */
    OPERATION,

    // ========================================================================
    // NETWORK CATEGORIES
    // ========================================================================

    /**
     * Network-related errors.
     */
    NETWORK,

    // ========================================================================
    // MODEL CATEGORIES
    // ========================================================================

    /**
     * Model loading and management errors.
     */
    MODEL,

    // ========================================================================
    // PLATFORM CATEGORIES
    // ========================================================================

    /**
     * Platform adapter and integration errors.
     */
    PLATFORM,

    // ========================================================================
    // AI COMPONENT CATEGORIES
    // ========================================================================

    /**
     * Large Language Model (LLM) errors.
     */
    LLM,

    /**
     * Speech-to-Text (STT) errors.
     */
    STT,

    /**
     * Text-to-Speech (TTS) errors.
     */
    TTS,

    /**
     * Voice Activity Detection (VAD) errors.
     */
    VAD,

    /**
     * Voice Agent pipeline errors.
     */
    VOICE_AGENT,

    // ========================================================================
    // DOWNLOAD CATEGORIES
    // ========================================================================

    /**
     * Download-related errors.
     */
    DOWNLOAD,

    // ========================================================================
    // AUTHENTICATION CATEGORIES
    // ========================================================================

    /**
     * Authentication and authorization errors.
     */
    AUTHENTICATION,

    ;

    /**
     * A human-readable description of the error category.
     */
    val description: String
        get() =
            when (this) {
                GENERAL -> "General error"
                CONFIGURATION -> "Configuration error"
                INITIALIZATION -> "Initialization error"
                FILE_RESOURCE -> "File or resource error"
                MEMORY -> "Memory allocation error"
                STORAGE -> "Storage error"
                OPERATION -> "Operation lifecycle error"
                NETWORK -> "Network error"
                MODEL -> "Model error"
                PLATFORM -> "Platform integration error"
                LLM -> "Language model error"
                STT -> "Speech-to-text error"
                TTS -> "Text-to-speech error"
                VAD -> "Voice activity detection error"
                VOICE_AGENT -> "Voice agent error"
                DOWNLOAD -> "Download error"
                AUTHENTICATION -> "Authentication error"
            }

    companion object {
        /**
         * Get the error category for a given error code.
         *
         * @param errorCode The error code to categorize
         * @return The corresponding error category
         */
        fun fromErrorCode(errorCode: ErrorCode): ErrorCategory {
            return when (errorCode) {
                // General errors
                ErrorCode.SUCCESS -> GENERAL
                ErrorCode.UNKNOWN -> GENERAL
                ErrorCode.INVALID_ARGUMENT -> CONFIGURATION

                // Initialization errors
                ErrorCode.NOT_INITIALIZED -> INITIALIZATION
                ErrorCode.ALREADY_INITIALIZED -> INITIALIZATION

                // Memory errors
                ErrorCode.OUT_OF_MEMORY -> MEMORY

                // File/resource errors
                ErrorCode.FILE_NOT_FOUND -> FILE_RESOURCE
                ErrorCode.MODEL_NOT_FOUND -> MODEL

                // Operation errors
                ErrorCode.TIMEOUT -> OPERATION
                ErrorCode.CANCELLED -> OPERATION

                // Network errors
                ErrorCode.NETWORK_UNAVAILABLE -> NETWORK
                ErrorCode.NETWORK_ERROR -> NETWORK

                // Model errors
                ErrorCode.MODEL_NOT_LOADED -> MODEL
                ErrorCode.MODEL_LOAD_FAILED -> MODEL

                // Platform errors
                ErrorCode.PLATFORM_ADAPTER_NOT_SET -> PLATFORM
                ErrorCode.INVALID_HANDLE -> PLATFORM

                // AI Component errors
                ErrorCode.STT_TRANSCRIPTION_FAILED -> STT
                ErrorCode.TTS_SYNTHESIS_FAILED -> TTS
                ErrorCode.LLM_GENERATION_FAILED -> LLM
                ErrorCode.VAD_DETECTION_FAILED -> VAD
                ErrorCode.VOICE_AGENT_ERROR -> VOICE_AGENT

                // Download errors
                ErrorCode.DOWNLOAD_FAILED -> DOWNLOAD
                ErrorCode.DOWNLOAD_CANCELLED -> DOWNLOAD
                ErrorCode.INSUFFICIENT_STORAGE -> STORAGE

                // Authentication errors
                ErrorCode.AUTHENTICATION_FAILED -> AUTHENTICATION
                ErrorCode.INVALID_API_KEY -> AUTHENTICATION
                ErrorCode.UNAUTHORIZED -> AUTHENTICATION
            }
        }
    }
}
