package com.runanywhere.sdk.core.bridge

/**
 * Result from TTS synthesis operation.
 * Contains audio samples and sample rate.
 */
data class TTSSynthesisResult(
    val samples: FloatArray,
    val sampleRate: Int
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false

        other as TTSSynthesisResult

        if (!samples.contentEquals(other.samples)) return false
        if (sampleRate != other.sampleRate) return false

        return true
    }

    override fun hashCode(): Int {
        var result = samples.contentHashCode()
        result = 31 * result + sampleRate
        return result
    }
}

/**
 * Result from VAD process operation.
 * Contains speech detection status and probability.
 */
data class VADResult(
    val isSpeech: Boolean,
    val probability: Float
)

/**
 * Exception thrown when a RunAnywhere operation fails.
 */
class RunAnywhereException(
    val resultCode: ResultCode,
    message: String? = null
) : Exception(message ?: "Operation failed with code: ${resultCode.name}")
