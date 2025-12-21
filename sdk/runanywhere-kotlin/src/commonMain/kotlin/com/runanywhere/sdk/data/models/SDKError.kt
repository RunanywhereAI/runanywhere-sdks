package com.runanywhere.sdk.data.models

import com.runanywhere.sdk.foundation.ErrorCategory
import com.runanywhere.sdk.foundation.ErrorCode

/**
 * SDK Error Hierarchy
 * Defines all possible SDK errors with numeric error codes matching iOS.
 *
 * Each error type maps to a numeric ErrorCode for structured error handling
 * and consistent error reporting across platforms.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Errors/RunAnywhereError.swift
 */
sealed class SDKError : Exception() {
    /**
     * Get the numeric error code for this error.
     * Matches iOS SDKErrorProtocol.code property.
     */
    open val errorCode: ErrorCode
        get() = ErrorCode.UNKNOWN

    /**
     * Get the error category for grouping and filtering.
     * Matches iOS ErrorCategory.
     */
    val category: ErrorCategory
        get() = ErrorCategory.from(errorCode)
    // Initialization errors
    object NotInitialized : SDKError() {
        override val message = "SDK not initialized. Call RunAnywhere.initialize() first"
        override val errorCode = ErrorCode.NOT_INITIALIZED
    }

    data class InitializationFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.NOT_INITIALIZED
    }

    // Model-related errors
    data class ModelNotFound(
        val modelId: String,
    ) : SDKError() {
        override val message = "Model not found: $modelId"
        override val errorCode = ErrorCode.MODEL_NOT_FOUND
    }

    data class ModelLoadingFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.MODEL_LOAD_FAILED
    }

    data class ModelDownloadFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.DOWNLOAD_FAILED
    }

    data class ModelRegistrationFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.MODEL_VALIDATION_FAILED
    }

    // File system errors
    data class FileSystemError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.FILE_ACCESS_DENIED
    }

    data class FileNotFound(
        val path: String,
    ) : SDKError() {
        override val message = "File not found: $path"
        override val errorCode = ErrorCode.FILE_NOT_FOUND
    }

    // Network errors
    data class NetworkError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.NETWORK_UNAVAILABLE
    }

    data class AuthenticationError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.AUTHENTICATION_FAILED
    }

    data class Timeout(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.NETWORK_TIMEOUT
    }

    data class ServerError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.API_ERROR
    }

    // Security errors
    data class SecurityError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.AUTHORIZATION_DENIED
    }

    // Storage errors
    data class StorageError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.STORAGE_FULL
    }

    // Configuration errors
    data class ConfigurationError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.INVALID_INPUT
    }

    data class InvalidConfiguration(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.INVALID_INPUT
    }

    // Runtime errors
    data class RuntimeError(
        override val message: String,
    ) : SDKError()

    data class ComponentNotAvailable(
        val component: String,
    ) : SDKError() {
        override val message = "Component not available: $component"
        override val errorCode = ErrorCode.NOT_INITIALIZED
    }

    // Component errors
    data class InvalidState(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.INVALID_INPUT
    }

    data class ComponentNotReady(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.NOT_INITIALIZED
    }

    data class ComponentNotInitialized(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.NOT_INITIALIZED
    }

    data class ServiceNotAvailable(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.HARDWARE_UNAVAILABLE
    }

    data class ComponentError(
        val component: String,
        override val message: String,
    ) : SDKError()

    data class ComponentFailure(
        override val message: String,
    ) : SDKError()

    // Validation errors
    data class ValidationError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.INVALID_INPUT
    }

    data class ValidationFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.MODEL_VALIDATION_FAILED
    }

    data class InvalidInput(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.INVALID_INPUT
    }

    // Transcription errors
    data class TranscriptionFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.GENERATION_FAILED
    }

    // API Key errors
    data class InvalidAPIKey(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.API_KEY_INVALID
    }

    // Device registration errors
    data class DeviceRegistrationError(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.AUTHENTICATION_FAILED
    }

    // Loading errors
    data class LoadingFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.MODEL_LOAD_FAILED
    }

    // Extension error types for public API
    data class ComponentInitializationFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.NOT_INITIALIZED
    }

    data class SessionNotFound(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.FILE_NOT_FOUND
    }

    data class DataRetrievalFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.API_ERROR
    }

    data class DataExportFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.FILE_ACCESS_DENIED
    }

    data class ModelLoadFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.MODEL_LOAD_FAILED
    }

    data class ModelOperationFailed(
        override val message: String,
    ) : SDKError()

    data class PipelineNotFound(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.FILE_NOT_FOUND
    }

    data class PipelineExecutionFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.GENERATION_FAILED
    }

    data class StructuredOutputParsingFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.INVALID_INPUT
    }

    data class StructuredOutputGenerationFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.GENERATION_FAILED
    }

    data class ProcessingFailed(
        override val message: String,
    ) : SDKError() {
        override val errorCode = ErrorCode.GENERATION_FAILED
    }
}
