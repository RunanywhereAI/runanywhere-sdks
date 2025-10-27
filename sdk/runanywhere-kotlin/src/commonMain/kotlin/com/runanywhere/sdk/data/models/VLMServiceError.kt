package com.runanywhere.sdk.data.models

import com.runanywhere.sdk.components.ImageFormat
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.events.ComponentInitializationEvent

/**
 * VLM-specific error types
 * Follows SDK error pattern for consistent error handling
 */
sealed class VLMServiceError : SDKError() {

    // MARK: - Initialization Errors

    /** Service has not been initialized */
    object NotInitialized : VLMServiceError() {
        override val message = "VLM service not initialized"
    }

    /** Model loading failed */
    data class ModelLoadFailed(val msg: String) : VLMServiceError() {
        override val message = "Model load failed: $msg"
    }

    /** Vision projector (mmproj) loading failed */
    data class VisionProjectorLoadFailed(val msg: String) : VLMServiceError() {
        override val message = "Vision projector load failed: $msg"
    }

    /** Model validation failed */
    data class ModelValidationFailed(
        val msg: String,
        val validationErrors: List<String> = emptyList()
    ) : VLMServiceError() {
        override val message = "Model validation failed: $msg"
    }

    // MARK: - Image Processing Errors

    /** Image encoding failed */
    data class ImageEncodingFailed(val msg: String) : VLMServiceError() {
        override val message = "Image encoding failed: $msg"
    }

    /** Image integration with LLM context failed */
    data class ImageIntegrationFailed(val msg: String) : VLMServiceError() {
        override val message = "Image integration failed: $msg"
    }

    /** Invalid image format */
    data class InvalidImageFormat(
        val format: String
    ) : VLMServiceError() {
        override val message = "Invalid image format: $format. Supported: ${ImageFormat.supportedFormats().joinToString()}"
    }

    /** Image size exceeds limits */
    data class ImageTooLarge(
        val maxSize: Long,
        val actualSize: Long
    ) : VLMServiceError() {
        override val message = "Image too large: ${actualSize / 1_000_000}MB exceeds max ${maxSize / 1_000_000}MB"
    }

    /** Image dimensions invalid */
    data class InvalidImageDimensions(
        val width: Int,
        val height: Int
    ) : VLMServiceError() {
        override val message = "Invalid image dimensions: ${width}x${height}"
    }

    // MARK: - Resource Errors

    /** Insufficient memory for model */
    data class InsufficientMemory(
        val required: Long,
        val available: Long
    ) : VLMServiceError() {
        override val message = "Insufficient memory: need ${required / 1_000_000}MB, have ${available / 1_000_000}MB"
    }

    /** Model file not found */
    data class ModelNotFound(val modelPath: String) : VLMServiceError() {
        override val message = "Model file not found: $modelPath"
    }

    /** Vision projector file not found */
    data class VisionProjectorNotFound(val projectorPath: String) : VLMServiceError() {
        override val message = "Vision projector file not found: $projectorPath"
    }

    /** No VLM provider available */
    object NoProviderAvailable : VLMServiceError() {
        override val message = "No VLM service provider registered for this model"
    }

    // MARK: - Runtime Errors

    /** Inference execution error */
    data class InferenceError(val msg: String) : VLMServiceError() {
        override val message = "Inference error: $msg"
    }

    /** Processing timeout */
    data class TimeoutError(val timeoutMs: Long) : VLMServiceError() {
        override val message = "Processing timed out after ${timeoutMs / 1000} seconds"
    }

    /** Context size exceeded */
    data class ContextSizeExceeded(
        val contextSize: Int,
        val required: Int
    ) : VLMServiceError() {
        override val message = "Context size exceeded: required $required, available $contextSize"
    }

    /** Generation cancelled */
    object GenerationCancelled : VLMServiceError() {
        override val message = "VLM generation was cancelled"
    }

    // MARK: - Configuration Errors

    /** Invalid configuration */
    data class InvalidConfiguration(
        val msg: String,
        val configErrors: List<String> = emptyList()
    ) : VLMServiceError() {
        override val message = "Invalid configuration: $msg"
    }

    /** Unsupported feature */
    data class UnsupportedFeature(val feature: String) : VLMServiceError() {
        override val message = "Unsupported feature: $feature"
    }

    // MARK: - Helper Methods

    /**
     * Convert error to ComponentFailed event
     */
    fun toEvent(): ComponentInitializationEvent.ComponentFailed {
        return ComponentInitializationEvent.ComponentFailed(
            component = SDKComponent.VLM.name,
            error = this
        )
    }

    /**
     * Get user-friendly error message
     */
    fun getUserMessage(): String {
        return when (this) {
            is NotInitialized -> "VLM service needs to be initialized before use"
            is ModelLoadFailed -> "Failed to load VLM model: $msg"
            is VisionProjectorLoadFailed -> "Failed to load vision projector: $msg"
            is ImageEncodingFailed -> "Failed to process image: $msg"
            is InsufficientMemory -> "Not enough memory. Need ${required / 1_000_000}MB, have ${available / 1_000_000}MB"
            is ModelNotFound -> "Model file not found at: $modelPath"
            is VisionProjectorNotFound -> "Vision projector not found at: $projectorPath"
            is InvalidImageFormat -> "Unsupported image format: $format. Supported: ${ImageFormat.supportedFormats().joinToString()}"
            is ImageTooLarge -> "Image too large. Max: ${maxSize / 1_000_000}MB, actual: ${actualSize / 1_000_000}MB"
            is TimeoutError -> "Processing timed out after ${timeoutMs / 1000} seconds"
            is NoProviderAvailable -> "No VLM provider available. Please ensure llama.cpp VLM module is added as a dependency"
            is ImageIntegrationFailed -> "Image integration failed: $msg"
            is InvalidImageDimensions -> "Invalid image dimensions: ${width}x${height}"
            is InferenceError -> "Inference error: $msg"
            is ContextSizeExceeded -> "Context size exceeded: required $required, available $contextSize"
            is GenerationCancelled -> "VLM generation was cancelled"
            is InvalidConfiguration -> "Invalid configuration: $msg"
            is UnsupportedFeature -> "Unsupported feature: $feature"
            is ModelValidationFailed -> "Model validation failed: $msg"
        }
    }

    /**
     * Check if error is recoverable
     */
    fun isRecoverable(): Boolean {
        return when (this) {
            is TimeoutError, is GenerationCancelled -> true
            is InsufficientMemory, is ImageTooLarge -> true  // User can try with smaller image/model
            is InvalidImageFormat, is InvalidImageDimensions -> true  // User can provide different image
            else -> false
        }
    }

    /**
     * Get suggested recovery action
     */
    fun getRecoveryAction(): String? {
        return when (this) {
            is InsufficientMemory -> "Try using a smaller quantized model or increase available memory"
            is ImageTooLarge -> "Resize the image to a smaller resolution or compress it"
            is InvalidImageFormat -> "Convert image to one of the supported formats: ${ImageFormat.supportedFormats().joinToString()}"
            is ModelNotFound -> "Download the model using ModelManager or check the model path"
            is VisionProjectorNotFound -> "Ensure both LLM and vision projector files are present"
            is NoProviderAvailable -> "Add llama.cpp VLM module as a dependency and register it"
            is TimeoutError -> "Try increasing timeout or using a faster model"
            is InvalidConfiguration -> "Review configuration parameters: ${configErrors.joinToString()}"
            else -> null
        }
    }
}

/**
 * Result wrapper for VLM operations
 */
sealed class VLMResult<out T> {
    data class Success<T>(val value: T) : VLMResult<T>()
    data class Failure(val error: VLMServiceError) : VLMResult<Nothing>()

    fun getOrNull(): T? = when (this) {
        is Success -> value
        is Failure -> null
    }

    fun getOrThrow(): T = when (this) {
        is Success -> value
        is Failure -> throw error
    }

    inline fun <R> map(transform: (T) -> R): VLMResult<R> = when (this) {
        is Success -> Success(transform(value))
        is Failure -> this
    }

    inline fun onSuccess(action: (T) -> Unit): VLMResult<T> {
        if (this is Success) action(value)
        return this
    }

    inline fun onFailure(action: (VLMServiceError) -> Unit): VLMResult<T> {
        if (this is Failure) action(error)
        return this
    }
}
