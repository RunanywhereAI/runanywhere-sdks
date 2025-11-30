package com.runanywhere.sdk.native.bridge

/**
 * Result from TTS synthesis operation via native backend.
 * Contains audio samples and sample rate.
 */
data class NativeTTSSynthesisResult(
    val samples: FloatArray,
    val sampleRate: Int
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || this::class != other::class) return false

        other as NativeTTSSynthesisResult

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
 * Result from VAD process operation via native backend.
 * Contains speech detection status and probability.
 */
data class NativeVADResult(
    val isSpeech: Boolean,
    val probability: Float
)

/**
 * Exception thrown when a native RunAnywhere operation fails.
 */
class NativeBridgeException(
    val resultCode: NativeResultCode,
    message: String? = null
) : Exception(message ?: "Native operation failed with code: ${resultCode.name}")
