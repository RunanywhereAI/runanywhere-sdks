/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * SDK error class matching iOS SDKError for cross-platform consistency.
 */

package com.runanywhere.sdk.foundation.errors

/**
 * SDK error class representing errors from SDK operations.
 *
 * This data class matches the iOS SDK's SDKError struct for cross-platform consistency.
 * It combines an error code, category, and message, with optional underlying cause for debugging.
 *
 * Use the companion object factory methods to create errors for specific categories:
 * - `SDKError.stt(message)` for speech-to-text errors
 * - `SDKError.llm(message)` for LLM errors
 * - `SDKError.network(message)` for network errors
 * - etc.
 *
 * @property code The specific error code identifying the error type.
 * @property category The category grouping this error for easier handling.
 * @property message A human-readable message describing the error.
 * @property cause The underlying throwable cause, if any.
 */
data class SDKError(
    val code: ErrorCode,
    val category: ErrorCategory,
    override val message: String,
    override val cause: Throwable? = null
) : Exception(message, cause) {

    /**
     * Whether this error represents success (error code is SUCCESS).
     */
    val isSuccess: Boolean
        get() = code == ErrorCode.SUCCESS

    /**
     * Whether this error represents a failure (error code is not SUCCESS).
     */
    val isError: Boolean
        get() = code != ErrorCode.SUCCESS

    /**
     * A detailed description combining code, category, and message.
     */
    val detailedDescription: String
        get() = "[$category] ${code.name}: $message"

    override fun toString(): String = detailedDescription

    companion object {

        // ========================================================================
        // GENERAL ERROR FACTORIES
        // ========================================================================

        /**
         * Create a general/unknown error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to UNKNOWN)
         * @param cause The underlying throwable cause
         * @return An SDKError with GENERAL category
         */
        fun general(
            message: String,
            code: ErrorCode = ErrorCode.UNKNOWN,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.GENERAL,
            message = message,
            cause = cause
        )

        /**
         * Create an unknown error.
         *
         * @param message The error message
         * @param cause The underlying throwable cause
         * @return An SDKError with UNKNOWN code and GENERAL category
         */
        fun unknown(message: String, cause: Throwable? = null): SDKError =
            general(message, ErrorCode.UNKNOWN, cause)

        // ========================================================================
        // CONFIGURATION ERROR FACTORIES
        // ========================================================================

        /**
         * Create a configuration error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to INVALID_ARGUMENT)
         * @param cause The underlying throwable cause
         * @return An SDKError with CONFIGURATION category
         */
        fun configuration(
            message: String,
            code: ErrorCode = ErrorCode.INVALID_ARGUMENT,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.CONFIGURATION,
            message = message,
            cause = cause
        )

        /**
         * Create an invalid argument error.
         *
         * @param message The error message
         * @param cause The underlying throwable cause
         * @return An SDKError with INVALID_ARGUMENT code
         */
        fun invalidArgument(message: String, cause: Throwable? = null): SDKError =
            configuration(message, ErrorCode.INVALID_ARGUMENT, cause)

        // ========================================================================
        // INITIALIZATION ERROR FACTORIES
        // ========================================================================

        /**
         * Create an initialization error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to NOT_INITIALIZED)
         * @param cause The underlying throwable cause
         * @return An SDKError with INITIALIZATION category
         */
        fun initialization(
            message: String,
            code: ErrorCode = ErrorCode.NOT_INITIALIZED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.INITIALIZATION,
            message = message,
            cause = cause
        )

        /**
         * Create a not initialized error.
         *
         * @param component The component that is not initialized
         * @param cause The underlying throwable cause
         * @return An SDKError with NOT_INITIALIZED code
         */
        fun notInitialized(component: String, cause: Throwable? = null): SDKError =
            initialization("$component is not initialized", ErrorCode.NOT_INITIALIZED, cause)

        /**
         * Create an already initialized error.
         *
         * @param component The component that is already initialized
         * @param cause The underlying throwable cause
         * @return An SDKError with ALREADY_INITIALIZED code
         */
        fun alreadyInitialized(component: String, cause: Throwable? = null): SDKError =
            initialization("$component is already initialized", ErrorCode.ALREADY_INITIALIZED, cause)

        // ========================================================================
        // FILE/RESOURCE ERROR FACTORIES
        // ========================================================================

        /**
         * Create a file/resource error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to FILE_NOT_FOUND)
         * @param cause The underlying throwable cause
         * @return An SDKError with FILE_RESOURCE category
         */
        fun fileResource(
            message: String,
            code: ErrorCode = ErrorCode.FILE_NOT_FOUND,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.FILE_RESOURCE,
            message = message,
            cause = cause
        )

        /**
         * Create a file not found error.
         *
         * @param path The path of the file that was not found
         * @param cause The underlying throwable cause
         * @return An SDKError with FILE_NOT_FOUND code
         */
        fun fileNotFound(path: String, cause: Throwable? = null): SDKError =
            fileResource("File not found: $path", ErrorCode.FILE_NOT_FOUND, cause)

        // ========================================================================
        // MEMORY ERROR FACTORIES
        // ========================================================================

        /**
         * Create a memory error.
         *
         * @param message The error message
         * @param cause The underlying throwable cause
         * @return An SDKError with OUT_OF_MEMORY code and MEMORY category
         */
        fun memory(message: String, cause: Throwable? = null): SDKError = SDKError(
            code = ErrorCode.OUT_OF_MEMORY,
            category = ErrorCategory.MEMORY,
            message = message,
            cause = cause
        )

        /**
         * Create an out of memory error.
         *
         * @param operation The operation that ran out of memory
         * @param cause The underlying throwable cause
         * @return An SDKError with OUT_OF_MEMORY code
         */
        fun outOfMemory(operation: String, cause: Throwable? = null): SDKError =
            memory("Out of memory during: $operation", cause)

        // ========================================================================
        // STORAGE ERROR FACTORIES
        // ========================================================================

        /**
         * Create a storage error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to INSUFFICIENT_STORAGE)
         * @param cause The underlying throwable cause
         * @return An SDKError with STORAGE category
         */
        fun storage(
            message: String,
            code: ErrorCode = ErrorCode.INSUFFICIENT_STORAGE,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.STORAGE,
            message = message,
            cause = cause
        )

        /**
         * Create an insufficient storage error.
         *
         * @param requiredBytes The number of bytes required (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with INSUFFICIENT_STORAGE code
         */
        fun insufficientStorage(requiredBytes: Long? = null, cause: Throwable? = null): SDKError {
            val message = if (requiredBytes != null) {
                "Insufficient storage space. Required: ${requiredBytes / 1024 / 1024} MB"
            } else {
                "Insufficient storage space"
            }
            return storage(message, ErrorCode.INSUFFICIENT_STORAGE, cause)
        }

        // ========================================================================
        // OPERATION ERROR FACTORIES
        // ========================================================================

        /**
         * Create an operation error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to CANCELLED)
         * @param cause The underlying throwable cause
         * @return An SDKError with OPERATION category
         */
        fun operation(
            message: String,
            code: ErrorCode = ErrorCode.CANCELLED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.OPERATION,
            message = message,
            cause = cause
        )

        /**
         * Create a timeout error.
         *
         * @param operation The operation that timed out
         * @param timeoutMs The timeout duration in milliseconds (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with TIMEOUT code
         */
        fun timeout(operation: String, timeoutMs: Long? = null, cause: Throwable? = null): SDKError {
            val message = if (timeoutMs != null) {
                "$operation timed out after ${timeoutMs}ms"
            } else {
                "$operation timed out"
            }
            return operation(message, ErrorCode.TIMEOUT, cause)
        }

        /**
         * Create a cancelled error.
         *
         * @param operation The operation that was cancelled
         * @param cause The underlying throwable cause
         * @return An SDKError with CANCELLED code
         */
        fun cancelled(operation: String, cause: Throwable? = null): SDKError =
            operation("$operation was cancelled", ErrorCode.CANCELLED, cause)

        // ========================================================================
        // NETWORK ERROR FACTORIES
        // ========================================================================

        /**
         * Create a network error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to NETWORK_ERROR)
         * @param cause The underlying throwable cause
         * @return An SDKError with NETWORK category
         */
        fun network(
            message: String,
            code: ErrorCode = ErrorCode.NETWORK_ERROR,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.NETWORK,
            message = message,
            cause = cause
        )

        /**
         * Create a network unavailable error.
         *
         * @param cause The underlying throwable cause
         * @return An SDKError with NETWORK_UNAVAILABLE code
         */
        fun networkUnavailable(cause: Throwable? = null): SDKError =
            network("Network is unavailable", ErrorCode.NETWORK_UNAVAILABLE, cause)

        // ========================================================================
        // MODEL ERROR FACTORIES
        // ========================================================================

        /**
         * Create a model error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to MODEL_NOT_LOADED)
         * @param cause The underlying throwable cause
         * @return An SDKError with MODEL category
         */
        fun model(
            message: String,
            code: ErrorCode = ErrorCode.MODEL_NOT_LOADED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.MODEL,
            message = message,
            cause = cause
        )

        /**
         * Create a model not found error.
         *
         * @param modelId The ID of the model that was not found
         * @param cause The underlying throwable cause
         * @return An SDKError with MODEL_NOT_FOUND code
         */
        fun modelNotFound(modelId: String, cause: Throwable? = null): SDKError =
            model("Model not found: $modelId", ErrorCode.MODEL_NOT_FOUND, cause)

        /**
         * Create a model not loaded error.
         *
         * @param modelId The ID of the model that is not loaded (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with MODEL_NOT_LOADED code
         */
        fun modelNotLoaded(modelId: String? = null, cause: Throwable? = null): SDKError {
            val message = if (modelId != null) {
                "Model not loaded: $modelId"
            } else {
                "No model is loaded"
            }
            return model(message, ErrorCode.MODEL_NOT_LOADED, cause)
        }

        /**
         * Create a model load failed error.
         *
         * @param modelId The ID of the model that failed to load
         * @param reason The reason for the failure (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with MODEL_LOAD_FAILED code
         */
        fun modelLoadFailed(modelId: String, reason: String? = null, cause: Throwable? = null): SDKError {
            val message = if (reason != null) {
                "Failed to load model $modelId: $reason"
            } else {
                "Failed to load model: $modelId"
            }
            return model(message, ErrorCode.MODEL_LOAD_FAILED, cause)
        }

        // ========================================================================
        // PLATFORM ERROR FACTORIES
        // ========================================================================

        /**
         * Create a platform error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to INVALID_HANDLE)
         * @param cause The underlying throwable cause
         * @return An SDKError with PLATFORM category
         */
        fun platform(
            message: String,
            code: ErrorCode = ErrorCode.INVALID_HANDLE,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.PLATFORM,
            message = message,
            cause = cause
        )

        /**
         * Create a platform adapter not set error.
         *
         * @param cause The underlying throwable cause
         * @return An SDKError with PLATFORM_ADAPTER_NOT_SET code
         */
        fun platformAdapterNotSet(cause: Throwable? = null): SDKError =
            platform("Platform adapter not set", ErrorCode.PLATFORM_ADAPTER_NOT_SET, cause)

        /**
         * Create an invalid handle error.
         *
         * @param component The component with the invalid handle
         * @param cause The underlying throwable cause
         * @return An SDKError with INVALID_HANDLE code
         */
        fun invalidHandle(component: String, cause: Throwable? = null): SDKError =
            platform("Invalid handle for: $component", ErrorCode.INVALID_HANDLE, cause)

        // ========================================================================
        // LLM ERROR FACTORIES
        // ========================================================================

        /**
         * Create an LLM error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to LLM_GENERATION_FAILED)
         * @param cause The underlying throwable cause
         * @return An SDKError with LLM category
         */
        fun llm(
            message: String,
            code: ErrorCode = ErrorCode.LLM_GENERATION_FAILED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.LLM,
            message = message,
            cause = cause
        )

        /**
         * Create an LLM generation failed error.
         *
         * @param reason The reason for the failure (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with LLM_GENERATION_FAILED code
         */
        fun llmGenerationFailed(reason: String? = null, cause: Throwable? = null): SDKError {
            val message = if (reason != null) {
                "LLM generation failed: $reason"
            } else {
                "LLM generation failed"
            }
            return llm(message, ErrorCode.LLM_GENERATION_FAILED, cause)
        }

        // ========================================================================
        // STT ERROR FACTORIES
        // ========================================================================

        /**
         * Create an STT (speech-to-text) error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to STT_TRANSCRIPTION_FAILED)
         * @param cause The underlying throwable cause
         * @return An SDKError with STT category
         */
        fun stt(
            message: String,
            code: ErrorCode = ErrorCode.STT_TRANSCRIPTION_FAILED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.STT,
            message = message,
            cause = cause
        )

        /**
         * Create an STT transcription failed error.
         *
         * @param reason The reason for the failure (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with STT_TRANSCRIPTION_FAILED code
         */
        fun sttTranscriptionFailed(reason: String? = null, cause: Throwable? = null): SDKError {
            val message = if (reason != null) {
                "Speech-to-text transcription failed: $reason"
            } else {
                "Speech-to-text transcription failed"
            }
            return stt(message, ErrorCode.STT_TRANSCRIPTION_FAILED, cause)
        }

        // ========================================================================
        // TTS ERROR FACTORIES
        // ========================================================================

        /**
         * Create a TTS (text-to-speech) error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to TTS_SYNTHESIS_FAILED)
         * @param cause The underlying throwable cause
         * @return An SDKError with TTS category
         */
        fun tts(
            message: String,
            code: ErrorCode = ErrorCode.TTS_SYNTHESIS_FAILED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.TTS,
            message = message,
            cause = cause
        )

        /**
         * Create a TTS synthesis failed error.
         *
         * @param reason The reason for the failure (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with TTS_SYNTHESIS_FAILED code
         */
        fun ttsSynthesisFailed(reason: String? = null, cause: Throwable? = null): SDKError {
            val message = if (reason != null) {
                "Text-to-speech synthesis failed: $reason"
            } else {
                "Text-to-speech synthesis failed"
            }
            return tts(message, ErrorCode.TTS_SYNTHESIS_FAILED, cause)
        }

        // ========================================================================
        // VAD ERROR FACTORIES
        // ========================================================================

        /**
         * Create a VAD (voice activity detection) error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to VAD_DETECTION_FAILED)
         * @param cause The underlying throwable cause
         * @return An SDKError with VAD category
         */
        fun vad(
            message: String,
            code: ErrorCode = ErrorCode.VAD_DETECTION_FAILED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.VAD,
            message = message,
            cause = cause
        )

        /**
         * Create a VAD detection failed error.
         *
         * @param reason The reason for the failure (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with VAD_DETECTION_FAILED code
         */
        fun vadDetectionFailed(reason: String? = null, cause: Throwable? = null): SDKError {
            val message = if (reason != null) {
                "Voice activity detection failed: $reason"
            } else {
                "Voice activity detection failed"
            }
            return vad(message, ErrorCode.VAD_DETECTION_FAILED, cause)
        }

        // ========================================================================
        // VOICE AGENT ERROR FACTORIES
        // ========================================================================

        /**
         * Create a Voice Agent error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to VOICE_AGENT_ERROR)
         * @param cause The underlying throwable cause
         * @return An SDKError with VOICE_AGENT category
         */
        fun voiceAgent(
            message: String,
            code: ErrorCode = ErrorCode.VOICE_AGENT_ERROR,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.VOICE_AGENT,
            message = message,
            cause = cause
        )

        /**
         * Create a Voice Agent pipeline error.
         *
         * @param stage The pipeline stage that failed
         * @param reason The reason for the failure (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with VOICE_AGENT_ERROR code
         */
        fun voiceAgentPipeline(stage: String, reason: String? = null, cause: Throwable? = null): SDKError {
            val message = if (reason != null) {
                "Voice agent pipeline failed at $stage: $reason"
            } else {
                "Voice agent pipeline failed at: $stage"
            }
            return voiceAgent(message, ErrorCode.VOICE_AGENT_ERROR, cause)
        }

        // ========================================================================
        // DOWNLOAD ERROR FACTORIES
        // ========================================================================

        /**
         * Create a download error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to DOWNLOAD_FAILED)
         * @param cause The underlying throwable cause
         * @return An SDKError with DOWNLOAD category
         */
        fun download(
            message: String,
            code: ErrorCode = ErrorCode.DOWNLOAD_FAILED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.DOWNLOAD,
            message = message,
            cause = cause
        )

        /**
         * Create a download failed error.
         *
         * @param url The URL that failed to download
         * @param reason The reason for the failure (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with DOWNLOAD_FAILED code
         */
        fun downloadFailed(url: String, reason: String? = null, cause: Throwable? = null): SDKError {
            val message = if (reason != null) {
                "Download failed for $url: $reason"
            } else {
                "Download failed: $url"
            }
            return download(message, ErrorCode.DOWNLOAD_FAILED, cause)
        }

        /**
         * Create a download cancelled error.
         *
         * @param url The URL whose download was cancelled
         * @param cause The underlying throwable cause
         * @return An SDKError with DOWNLOAD_CANCELLED code
         */
        fun downloadCancelled(url: String, cause: Throwable? = null): SDKError =
            download("Download cancelled: $url", ErrorCode.DOWNLOAD_CANCELLED, cause)

        // ========================================================================
        // AUTHENTICATION ERROR FACTORIES
        // ========================================================================

        /**
         * Create an authentication error.
         *
         * @param message The error message
         * @param code The specific error code (defaults to AUTHENTICATION_FAILED)
         * @param cause The underlying throwable cause
         * @return An SDKError with AUTHENTICATION category
         */
        fun authentication(
            message: String,
            code: ErrorCode = ErrorCode.AUTHENTICATION_FAILED,
            cause: Throwable? = null
        ): SDKError = SDKError(
            code = code,
            category = ErrorCategory.AUTHENTICATION,
            message = message,
            cause = cause
        )

        /**
         * Create an authentication failed error.
         *
         * @param reason The reason for the failure (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with AUTHENTICATION_FAILED code
         */
        fun authenticationFailed(reason: String? = null, cause: Throwable? = null): SDKError {
            val message = if (reason != null) {
                "Authentication failed: $reason"
            } else {
                "Authentication failed"
            }
            return authentication(message, ErrorCode.AUTHENTICATION_FAILED, cause)
        }

        /**
         * Create an invalid API key error.
         *
         * @param cause The underlying throwable cause
         * @return An SDKError with INVALID_API_KEY code
         */
        fun invalidApiKey(cause: Throwable? = null): SDKError =
            authentication("Invalid API key", ErrorCode.INVALID_API_KEY, cause)

        /**
         * Create an unauthorized error.
         *
         * @param resource The resource that is unauthorized (optional)
         * @param cause The underlying throwable cause
         * @return An SDKError with UNAUTHORIZED code
         */
        fun unauthorized(resource: String? = null, cause: Throwable? = null): SDKError {
            val message = if (resource != null) {
                "Unauthorized access to: $resource"
            } else {
                "Unauthorized access"
            }
            return authentication(message, ErrorCode.UNAUTHORIZED, cause)
        }

        // ========================================================================
        // C++ INTEROP FACTORIES
        // ========================================================================

        /**
         * Create an SDKError from a C++ raw error code.
         *
         * This is used for interop with the runanywhere-commons C++ library.
         *
         * @param rawValue The C++ error code value
         * @param message The error message (optional, will use default if not provided)
         * @param cause The underlying throwable cause
         * @return An SDKError corresponding to the raw error code
         */
        fun fromRawValue(rawValue: Int, message: String? = null, cause: Throwable? = null): SDKError {
            val errorCode = ErrorCode.fromRawValue(rawValue)
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
         * Create an SDKError from an ErrorCode.
         *
         * @param errorCode The error code
         * @param message The error message (optional, will use default if not provided)
         * @param cause The underlying throwable cause
         * @return An SDKError with the appropriate category
         */
        fun fromErrorCode(errorCode: ErrorCode, message: String? = null, cause: Throwable? = null): SDKError {
            val errorCategory = ErrorCategory.fromErrorCode(errorCode)
            val errorMessage = message ?: errorCode.description
            return SDKError(
                code = errorCode,
                category = errorCategory,
                message = errorMessage,
                cause = cause
            )
        }
    }
}
