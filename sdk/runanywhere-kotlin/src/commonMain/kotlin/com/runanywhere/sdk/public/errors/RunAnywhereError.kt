package com.runanywhere.sdk.public.errors

/**
 * Main public error type for the RunAnywhere SDK.
 * All SDK errors should use this type for consistent error handling.
 *
 * Aligned with iOS: `RunAnywhere/Public/Errors/RunAnywhereError.swift`
 */
sealed class RunAnywhereError(
    override val message: String,
    override val cause: Throwable? = null
) : Exception(message, cause) {

    /**
     * The error code for machine-readable identification.
     */
    abstract val code: ErrorCode

    /**
     * The category of this error for grouping/filtering.
     */
    abstract val category: ErrorCategory

    /**
     * The underlying error that caused this error, if any.
     */
    val underlyingError: Throwable? get() = cause

    /**
     * User-friendly error description.
     */
    open val errorDescription: String get() = message

    /**
     * Recovery suggestion for the user.
     */
    abstract val recoverySuggestion: String?

    // ============================================================================
    // MARK: - Initialization Errors
    // ============================================================================

    data object NotInitialized : RunAnywhereError("RunAnywhere SDK is not initialized. Call initialize() first.") {
        override val code = ErrorCode.NOT_INITIALIZED
        override val category = ErrorCategory.INITIALIZATION
        override val recoverySuggestion = "Call RunAnywhere.initialize() before using the SDK."
    }

    data object AlreadyInitialized : RunAnywhereError("RunAnywhere SDK is already initialized.") {
        override val code = ErrorCode.ALREADY_INITIALIZED
        override val category = ErrorCategory.INITIALIZATION
        override val recoverySuggestion = "The SDK is already initialized. You can use it directly."
    }

    data class InvalidConfiguration(val detail: String) :
        RunAnywhereError("Invalid configuration: $detail") {
        override val code = ErrorCode.INVALID_INPUT
        override val category = ErrorCategory.INITIALIZATION
        override val recoverySuggestion = "Check your configuration settings and ensure all required fields are provided."
    }

    data class InvalidAPIKey(val reason: String?) :
        RunAnywhereError(reason?.let { "Invalid API key: $it" } ?: "Invalid or missing API key.") {
        override val code = ErrorCode.API_KEY_INVALID
        override val category = ErrorCategory.INITIALIZATION
        override val recoverySuggestion = "Provide a valid API key in the configuration."
    }

    data class EnvironmentMismatch(val reason: String) :
        RunAnywhereError("Environment configuration mismatch: $reason") {
        override val code = ErrorCode.INVALID_INPUT
        override val category = ErrorCategory.INITIALIZATION
        override val recoverySuggestion = "Use .development or .staging for DEBUG builds. Production environment requires a Release build."
    }

    // ============================================================================
    // MARK: - Model Errors
    // ============================================================================

    data class ModelNotFound(val identifier: String) :
        RunAnywhereError("Model '$identifier' not found.") {
        override val code = ErrorCode.MODEL_NOT_FOUND
        override val category = ErrorCategory.MODEL
        override val recoverySuggestion = "Check the model identifier or download the model first."
    }

    data class ModelLoadFailed(val identifier: String, override val cause: Throwable? = null) :
        RunAnywhereError(
            cause?.let { "Failed to load model '$identifier': ${it.message}" }
                ?: "Failed to load model '$identifier'",
            cause
        ) {
        override val code = ErrorCode.MODEL_LOAD_FAILED
        override val category = ErrorCategory.MODEL
        override val recoverySuggestion = "Ensure the model file is not corrupted and is compatible with your device."
    }

    data class LoadingFailed(val reason: String) :
        RunAnywhereError("Failed to load: $reason") {
        override val code = ErrorCode.MODEL_LOAD_FAILED
        override val category = ErrorCategory.MODEL
        override val recoverySuggestion = "Ensure the model file is not corrupted and is compatible with your device."
    }

    data class ModelValidationFailed(val identifier: String, val errors: List<String>) :
        RunAnywhereError("Model '$identifier' validation failed: ${errors.joinToString(", ")}") {
        override val code = ErrorCode.MODEL_VALIDATION_FAILED
        override val category = ErrorCategory.MODEL
        override val recoverySuggestion = "The model file may be corrupted or incompatible. Try re-downloading."
    }

    data class ModelIncompatible(val identifier: String, val reason: String) :
        RunAnywhereError("Model '$identifier' is incompatible: $reason") {
        override val code = ErrorCode.MODEL_INCOMPATIBLE
        override val category = ErrorCategory.MODEL
        override val recoverySuggestion = "Use a different model that is compatible with your device."
    }

    // ============================================================================
    // MARK: - Generation Errors
    // ============================================================================

    data class GenerationFailed(val reason: String) :
        RunAnywhereError("Text generation failed: $reason") {
        override val code = ErrorCode.GENERATION_FAILED
        override val category = ErrorCategory.GENERATION
        override val recoverySuggestion = "Check your input and try again."
    }

    data class GenerationTimeout(val reason: String? = null) :
        RunAnywhereError(reason?.let { "Generation timed out: $it" } ?: "Text generation timed out.") {
        override val code = ErrorCode.GENERATION_TIMEOUT
        override val category = ErrorCategory.GENERATION
        override val recoverySuggestion = "Try with a shorter prompt or fewer tokens."
    }

    data class ContextTooLong(val provided: Int, val maximum: Int) :
        RunAnywhereError("Context too long: $provided tokens (maximum: $maximum)") {
        override val code = ErrorCode.CONTEXT_TOO_LONG
        override val category = ErrorCategory.GENERATION
        override val recoverySuggestion = "Reduce the context size or use a model with larger context window."
    }

    data class TokenLimitExceeded(val requested: Int, val maximum: Int) :
        RunAnywhereError("Token limit exceeded: requested $requested, maximum $maximum") {
        override val code = ErrorCode.TOKEN_LIMIT_EXCEEDED
        override val category = ErrorCategory.GENERATION
        override val recoverySuggestion = "Reduce the number of tokens requested."
    }

    data class CostLimitExceeded(val estimated: Double, val limit: Double) :
        RunAnywhereError("Cost limit exceeded: estimated ${"$%.2f".format(estimated)}, limit ${"$%.2f".format(limit)}") {
        override val code = ErrorCode.COST_LIMIT_EXCEEDED
        override val category = ErrorCategory.GENERATION
        override val recoverySuggestion = "Increase your cost limit or use a more cost-effective model."
    }

    // ============================================================================
    // MARK: - Network Errors
    // ============================================================================

    data object NetworkUnavailable : RunAnywhereError("Network connection unavailable.") {
        override val code = ErrorCode.NETWORK_UNAVAILABLE
        override val category = ErrorCategory.NETWORK
        override val recoverySuggestion = "Check your internet connection and try again."
    }

    data class NetworkError(val reason: String) :
        RunAnywhereError("Network error: $reason") {
        override val code = ErrorCode.API_ERROR
        override val category = ErrorCategory.NETWORK
        override val recoverySuggestion = "Check your internet connection and try again."
    }

    data class RequestFailed(override val cause: Throwable) :
        RunAnywhereError("Request failed: ${cause.message}", cause) {
        override val code = ErrorCode.API_ERROR
        override val category = ErrorCategory.NETWORK
        override val recoverySuggestion = "Check your internet connection and try again."
    }

    data class DownloadFailed(val url: String, override val cause: Throwable? = null) :
        RunAnywhereError(
            cause?.let { "Failed to download from '$url': ${it.message}" }
                ?: "Failed to download from '$url'",
            cause
        ) {
        override val code = ErrorCode.DOWNLOAD_FAILED
        override val category = ErrorCategory.NETWORK
        override val recoverySuggestion = "Check your internet connection and available storage space."
    }

    data class ServerError(val reason: String) :
        RunAnywhereError("Server error: $reason") {
        override val code = ErrorCode.API_ERROR
        override val category = ErrorCategory.NETWORK
        override val recoverySuggestion = "Check your internet connection and try again."
    }

    data class Timeout(val reason: String) :
        RunAnywhereError("Operation timed out: $reason") {
        override val code = ErrorCode.NETWORK_TIMEOUT
        override val category = ErrorCategory.NETWORK
        override val recoverySuggestion = "The operation timed out. Try again or check your network connection."
    }

    // ============================================================================
    // MARK: - Storage Errors
    // ============================================================================

    data class InsufficientStorage(val required: Long, val available: Long) :
        RunAnywhereError("Insufficient storage: ${formatBytes(required)} required, ${formatBytes(available)} available") {
        override val code = ErrorCode.INSUFFICIENT_STORAGE
        override val category = ErrorCategory.STORAGE
        override val recoverySuggestion = "Free up storage space on your device."
    }

    data object StorageFull : RunAnywhereError("Device storage is full.") {
        override val code = ErrorCode.STORAGE_FULL
        override val category = ErrorCategory.STORAGE
        override val recoverySuggestion = "Delete unnecessary files to free up space."
    }

    data class StorageError(val reason: String) :
        RunAnywhereError("Storage error: $reason") {
        override val code = ErrorCode.FILE_ACCESS_DENIED
        override val category = ErrorCategory.STORAGE
        override val recoverySuggestion = "Free up storage space on your device."
    }

    // ============================================================================
    // MARK: - Hardware Errors
    // ============================================================================

    data class HardwareUnsupported(val feature: String) :
        RunAnywhereError("Hardware does not support $feature.") {
        override val code = ErrorCode.HARDWARE_UNSUPPORTED
        override val category = ErrorCategory.HARDWARE
        override val recoverySuggestion = "Use a different model or device that supports this feature."
    }

    // ============================================================================
    // MARK: - Component Errors
    // ============================================================================

    data class ComponentNotInitialized(val component: String) :
        RunAnywhereError("Component not initialized: $component") {
        override val code = ErrorCode.NOT_INITIALIZED
        override val category = ErrorCategory.COMPONENT
        override val recoverySuggestion = "Ensure the component is properly initialized before use."
    }

    data class ComponentNotReady(val component: String) :
        RunAnywhereError("Component not ready: $component") {
        override val code = ErrorCode.NOT_INITIALIZED
        override val category = ErrorCategory.COMPONENT
        override val recoverySuggestion = "Ensure the component is properly initialized before use."
    }

    data class InvalidState(val reason: String) :
        RunAnywhereError("Invalid state: $reason") {
        override val code = ErrorCode.INVALID_INPUT
        override val category = ErrorCategory.COMPONENT
        override val recoverySuggestion = "Check the current state and ensure operations are called in the correct order."
    }

    // ============================================================================
    // MARK: - Validation Errors
    // ============================================================================

    data class ValidationFailed(val reason: String) :
        RunAnywhereError("Validation failed: $reason") {
        override val code = ErrorCode.INVALID_INPUT
        override val category = ErrorCategory.VALIDATION
        override val recoverySuggestion = "Check your input parameters and ensure they are valid."
    }

    data class UnsupportedModality(val modality: String) :
        RunAnywhereError("Unsupported modality: $modality") {
        override val code = ErrorCode.INVALID_INPUT
        override val category = ErrorCategory.VALIDATION
        override val recoverySuggestion = "Check your input parameters and ensure they are valid."
    }

    // ============================================================================
    // MARK: - Authentication Errors
    // ============================================================================

    data class AuthenticationFailed(val reason: String) :
        RunAnywhereError("Authentication failed: $reason") {
        override val code = ErrorCode.AUTHENTICATION_FAILED
        override val category = ErrorCategory.AUTHENTICATION
        override val recoverySuggestion = "Check your credentials and try again."
    }

    // ============================================================================
    // MARK: - Framework Errors
    // ============================================================================

    data class FrameworkNotAvailable(val framework: String) :
        RunAnywhereError("Framework $framework not available") {
        override val code = ErrorCode.HARDWARE_UNAVAILABLE
        override val category = ErrorCategory.FRAMEWORK
        override val recoverySuggestion = "Use a different model or device that supports this feature."
    }

    data class DatabaseInitializationFailed(override val cause: Throwable) :
        RunAnywhereError("Database initialization failed: ${cause.message}", cause) {
        override val code = ErrorCode.UNKNOWN
        override val category = ErrorCategory.FRAMEWORK
        override val recoverySuggestion = "Try reinstalling the app or clearing app data."
    }

    // ============================================================================
    // MARK: - Feature Errors
    // ============================================================================

    data class FeatureNotAvailable(val feature: String) :
        RunAnywhereError("Feature '$feature' is not available.") {
        override val code = ErrorCode.UNKNOWN
        override val category = ErrorCategory.UNKNOWN
        override val recoverySuggestion = "This feature may be available in a future update."
    }

    data class NotImplemented(val feature: String) :
        RunAnywhereError("Feature '$feature' is not yet implemented.") {
        override val code = ErrorCode.UNKNOWN
        override val category = ErrorCategory.UNKNOWN
        override val recoverySuggestion = "This feature may be available in a future update."
    }

    companion object {
        /**
         * Format bytes to human-readable string.
         */
        private fun formatBytes(bytes: Long): String {
            val units = arrayOf("B", "KB", "MB", "GB", "TB")
            var value = bytes.toDouble()
            var unitIndex = 0
            while (value >= 1024 && unitIndex < units.size - 1) {
                value /= 1024
                unitIndex++
            }
            return "%.1f %s".format(value, units[unitIndex])
        }
    }
}

/**
 * Type alias for convenience.
 */
typealias SDKError = RunAnywhereError
