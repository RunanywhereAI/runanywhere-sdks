package com.runanywhere.sdk.core.onnx

/**
 * Error types for ONNX Runtime operations.
 *
 * Note: Only includes error types that are actually used in the codebase.
 * Additional error types can be added when needed.
 */
sealed class ONNXError : Exception() {
    /** Model loading failed */
    data class ModelLoadFailed(
        val details: String,
    ) : ONNXError() {
        override val message: String = "Model load failed: $details"
    }

    /** Model not downloaded */
    data class ModelNotFound(
        val modelId: String,
    ) : ONNXError() {
        override val message: String = "Model not found or not downloaded: $modelId"
    }
}
