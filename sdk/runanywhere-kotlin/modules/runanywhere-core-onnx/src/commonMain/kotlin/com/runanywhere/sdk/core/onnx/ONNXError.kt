package com.runanywhere.sdk.core.onnx

/**
 * Error types for ONNX Runtime operations
 * Matches iOS ONNXError enum
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXError.swift
 */
sealed class ONNXError : Exception() {

    /** Backend handle is invalid or null */
    object InvalidHandle : ONNXError() {
        private fun readResolve(): Any = InvalidHandle
        override val message: String = "Invalid backend handle"
    }

    /** Backend initialization failed */
    object InitializationFailed : ONNXError() {
        private fun readResolve(): Any = InitializationFailed
        override val message: String = "ONNX Runtime initialization failed"
    }

    /** Model loading failed */
    data class ModelLoadFailed(val details: String) : ONNXError() {
        override val message: String = "Model load failed: $details"
    }

    /** Inference failed */
    data class InferenceFailed(val details: String) : ONNXError() {
        override val message: String = "Inference failed: $details"
    }

    /** Invalid parameters provided */
    object InvalidParameters : ONNXError() {
        private fun readResolve(): Any = InvalidParameters
        override val message: String = "Invalid parameters"
    }

    /** Feature not implemented */
    object NotImplemented : ONNXError() {
        private fun readResolve(): Any = NotImplemented
        override val message: String = "Feature not implemented"
    }

    /** Transcription failed */
    data class TranscriptionFailed(val details: String) : ONNXError() {
        override val message: String = "Transcription failed: $details"
    }

    /** Synthesis failed */
    data class SynthesisFailed(val details: String) : ONNXError() {
        override val message: String = "Synthesis failed: $details"
    }

    /** Model not downloaded */
    data class ModelNotFound(val modelId: String) : ONNXError() {
        override val message: String = "Model not found or not downloaded: $modelId"
    }

    /** Unknown error from native code */
    data class Unknown(val code: Int) : ONNXError() {
        override val message: String = "Unknown error (code: $code)"
    }

    companion object {
        /**
         * Map native error code to ONNXError
         * Matches iOS ONNXError.from(code:) method
         */
        fun fromCode(code: Int): ONNXError {
            return when (code) {
                0 -> throw IllegalArgumentException("Code 0 is success, not an error")
                -1 -> InitializationFailed
                -2 -> ModelLoadFailed("Unknown")
                -3 -> InferenceFailed("Unknown")
                -4 -> InvalidHandle
                -5 -> InvalidParameters
                -6 -> InferenceFailed("Out of memory")
                -7 -> NotImplemented
                -8 -> InferenceFailed("Cancelled")
                -9 -> InferenceFailed("Timeout")
                -10 -> InferenceFailed("IO error")
                else -> Unknown(code)
            }
        }
    }
}
