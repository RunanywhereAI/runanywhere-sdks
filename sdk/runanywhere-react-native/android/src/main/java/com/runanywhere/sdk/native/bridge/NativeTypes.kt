package com.runanywhere.sdk.native.bridge

/**
 * Native JNI result types
 *
 * These classes MUST be in this exact package to match the JNI expectations
 * in runanywhere-core/src/bridge/jni/runanywhere_jni.cpp
 */

/**
 * Result class for TTS synthesis - used by JNI
 */
data class NativeTTSSynthesisResult(
    val samples: FloatArray,
    val sampleRate: Int
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
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
 * Result class for VAD processing - used by JNI
 */
data class NativeVADResult(
    val isSpeech: Boolean,
    val probability: Float
)
