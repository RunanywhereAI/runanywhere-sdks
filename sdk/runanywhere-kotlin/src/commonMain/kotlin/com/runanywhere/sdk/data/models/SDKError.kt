package com.runanywhere.sdk.data.models

/**
 * SDK Error Hierarchy
 * Defines all possible SDK errors
 */
sealed class SDKError : Exception() {

    // Initialization errors
    object NotInitialized : SDKError() {
        override val message = "SDK not initialized. Call RunAnywhere.initialize() first"
    }

    data class InitializationFailed(override val message: String) : SDKError()

    // Model-related errors
    data class ModelNotFound(val modelId: String) : SDKError() {
        override val message = "Model not found: $modelId"
    }

    data class ModelLoadingFailed(override val message: String) : SDKError()
    data class ModelDownloadFailed(override val message: String) : SDKError()

    // File system errors
    data class FileSystemError(override val message: String) : SDKError()
    data class FileNotFound(val path: String) : SDKError() {
        override val message = "File not found: $path"
    }

    // Network errors
    data class NetworkError(override val message: String) : SDKError()
    data class AuthenticationError(override val message: String) : SDKError()

    // Configuration errors
    data class ConfigurationError(override val message: String) : SDKError()
    data class InvalidConfiguration(override val message: String) : SDKError()

    // Runtime errors
    data class RuntimeError(override val message: String) : SDKError()
    data class ComponentNotAvailable(val component: String) : SDKError() {
        override val message = "Component not available: $component"
    }

    // Component errors
    data class InvalidState(override val message: String) : SDKError()
    data class ComponentNotReady(override val message: String) : SDKError()
    data class ComponentNotInitialized(override val message: String) : SDKError()
    data class ServiceNotAvailable(override val message: String) : SDKError()
    data class ComponentError(val component: String, override val message: String) : SDKError()
    data class ComponentFailure(override val message: String) : SDKError()

    // Validation errors
    data class ValidationError(override val message: String) : SDKError()
    data class ValidationFailed(override val message: String) : SDKError()
    data class InvalidInput(override val message: String) : SDKError()

    // Transcription errors
    data class TranscriptionFailed(override val message: String) : SDKError()

    // API Key errors
    data class InvalidAPIKey(override val message: String) : SDKError()

    // Alias for consistency with different naming conventions
    data class InvalidApiKey(override val message: String) : SDKError()

    // Loading errors
    data class LoadingFailed(override val message: String) : SDKError()

    // Extension error types for public API
    data class ComponentInitializationFailed(override val message: String) : SDKError()
    data class SessionNotFound(override val message: String) : SDKError()
    data class DataRetrievalFailed(override val message: String) : SDKError()
    data class DataExportFailed(override val message: String) : SDKError()
    data class ModelLoadFailed(override val message: String) : SDKError()
    data class ModelOperationFailed(override val message: String) : SDKError()
    data class PipelineNotFound(override val message: String) : SDKError()
    data class PipelineExecutionFailed(override val message: String) : SDKError()
    data class StructuredOutputParsingFailed(override val message: String) : SDKError()
    data class StructuredOutputGenerationFailed(override val message: String) : SDKError()
    data class ProcessingFailed(override val message: String) : SDKError()
}
