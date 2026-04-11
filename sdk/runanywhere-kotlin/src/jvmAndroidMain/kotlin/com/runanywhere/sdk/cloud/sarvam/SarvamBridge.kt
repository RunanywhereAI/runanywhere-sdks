package com.runanywhere.sdk.cloud.sarvam

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * JNI bridge for Sarvam AI cloud backend.
 * Maps to rac_backend_sarvam_jni.cpp in runanywhere-commons.
 */
internal object SarvamBridge {
    private val logger = SDKLogger("SarvamBridge")

    @Volatile
    private var isLoaded = false

    fun ensureLoaded() {
        if (isLoaded) return
        synchronized(this) {
            if (isLoaded) return
            try {
                System.loadLibrary("rac_backend_sarvam")
                isLoaded = true
                logger.info("Loaded librac_backend_sarvam.so")
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load librac_backend_sarvam.so: ${e.message}")
                throw e
            }
        }
    }

    @JvmStatic
    external fun nativeRegister(): Int

    @JvmStatic
    external fun nativeUnregister(): Int

    @JvmStatic
    external fun nativeSetApiKey(apiKey: String): Int

    @JvmStatic
    external fun nativeHasApiKey(): Boolean
}
