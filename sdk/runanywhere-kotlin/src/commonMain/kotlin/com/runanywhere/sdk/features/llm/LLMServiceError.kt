package com.runanywhere.sdk.features.llm

/**
 * Errors for LLM services - exact match with iOS LLMServiceError
 */
sealed class LLMServiceError : Exception() {
    /** Service is not initialized */
    object NotInitialized : LLMServiceError() {
        override val message: String = "LLM service is not initialized"
    }

    /** Model not found */
    data class ModelNotFound(
        val model: String,
    ) : LLMServiceError() {
        override val message: String = "Model not found: $model"
    }

    /** Generation failed */
    data class GenerationFailed(
        override val cause: Throwable,
    ) : LLMServiceError() {
        override val message: String = "Generation failed: ${cause.message}"
    }

    /** Streaming not supported */
    object StreamingNotSupported : LLMServiceError() {
        override val message: String = "Streaming generation is not supported"
    }

    /** Context length exceeded */
    object ContextLengthExceeded : LLMServiceError() {
        override val message: String = "Context length exceeded"
    }

    /** Invalid options */
    object InvalidOptions : LLMServiceError() {
        override val message: String = "Invalid generation options"
    }

    /** Model loading failed */
    data class ModelLoadFailed(
        val model: String,
        override val cause: Throwable,
    ) : LLMServiceError() {
        override val message: String = "Failed to load model: $model - ${cause.message}"
    }

    /** Service initialization failed */
    data class InitializationFailed(
        val reason: String,
    ) : LLMServiceError() {
        override val message: String = "LLM service initialization failed: $reason"
    }

    /** Insufficient memory */
    data class InsufficientMemory(
        val required: Long,
        val available: Long,
    ) : LLMServiceError() {
        override val message: String = "Insufficient memory: required ${required / 1024 / 1024}MB, available ${available / 1024 / 1024}MB"
    }

    /** Unsupported model format */
    data class UnsupportedFormat(
        val format: String,
    ) : LLMServiceError() {
        override val message: String = "Unsupported model format: $format"
    }

    /** Generation timeout */
    data class GenerationTimeout(
        val timeoutMs: Long,
    ) : LLMServiceError() {
        override val message: String = "Generation timed out after ${timeoutMs}ms"
    }

    /** Service unavailable */
    data class ServiceUnavailable(
        val reason: String,
    ) : LLMServiceError() {
        override val message: String = "LLM service unavailable: $reason"
    }

    /** Invalid input */
    data class InvalidInput(
        val reason: String,
    ) : LLMServiceError() {
        override val message: String = "Invalid input: $reason"
    }

    /** Model download failed */
    data class ModelDownloadFailed(
        val model: String,
        override val cause: Throwable,
    ) : LLMServiceError() {
        override val message: String = "Failed to download model: $model - ${cause.message}"
    }

    /** Hardware not supported */
    data class HardwareNotSupported(
        val hardware: String,
    ) : LLMServiceError() {
        override val message: String = "Hardware not supported: $hardware"
    }

    /** Framework not available */
    data class FrameworkNotAvailable(
        val framework: String,
    ) : LLMServiceError() {
        override val message: String = "Framework not available: $framework"
    }
}

/**
 * Extension functions for error handling
 */
fun Throwable.toLLMServiceError(): LLMServiceError =
    when (this) {
        is LLMServiceError -> this
        is IllegalArgumentException -> LLMServiceError.InvalidInput(message ?: "Invalid argument")
        is OutOfMemoryError -> LLMServiceError.InsufficientMemory(0L, 0L)
        is java.util.concurrent.TimeoutException -> LLMServiceError.GenerationTimeout(0L)
        else -> LLMServiceError.GenerationFailed(this)
    }

/**
 * Check if error is recoverable
 */
val LLMServiceError.isRecoverable: Boolean
    get() =
        when (this) {
            is LLMServiceError.NotInitialized -> true
            is LLMServiceError.InvalidOptions -> true
            is LLMServiceError.InvalidInput -> true
            is LLMServiceError.GenerationTimeout -> true
            is LLMServiceError.ServiceUnavailable -> true
            else -> false
        }
