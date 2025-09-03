package com.runanywhere.sdk.jni

/**
 * JNI interface for WebRTC Voice Activity Detection
 */
class WebRTCVadJNI {
    companion object {
        init {
            NativeLoader.loadLibrary("webrtc-vad-jni")
        }
    }

    /**
     * Initialize VAD with given parameters
     * @return pointer to the VAD instance
     */
    external fun initialize(aggressiveness: Int, sampleRate: Int): Long

    /**
     * Check if audio contains speech
     */
    external fun isSpeech(vadPtr: Long, audio: FloatArray): Boolean

    /**
     * Reset VAD state
     */
    external fun reset(vadPtr: Long)

    /**
     * Destroy VAD instance and free memory
     */
    external fun destroy(vadPtr: Long)
}
