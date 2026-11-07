/*
 * LiteRT-LM native bridge. librac_backend_litertlm_jni.so exposes
 * rac_backend_litertlm_register() and rac_backend_litertlm_unregister().
 */

package com.runanywhere.sdk.llm.litertlm

import com.runanywhere.sdk.infrastructure.logging.SDKLogger

internal object LiteRTLMBridge {
    private val logger = SDKLogger("LiteRTLM")

    @Volatile
    private var nativeLibraryLoaded = false

    private val loadLock = Any()

    /**
     * Loads the JNI library. librac_commons.so must already be loaded, through the
     * main SDK's librunanywhere_jni.so, so that the plugin registry resolves.
     */
    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true
        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true
            try {
                System.loadLibrary("rac_backend_litertlm_jni")
                nativeLibraryLoaded = true
                return true
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load LiteRT-LM native library: ${e.message}", throwable = e)
                return false
            }
        }
    }

    /** Registers the backend with the C++ plugin registry. 0 = success. */
    @JvmStatic
    external fun nativeRegister(): Int

    /** Unregisters the backend. 0 = success. */
    @JvmStatic
    external fun nativeUnregister(): Int

    /** Module version baked into the JNI library. */
    @JvmStatic
    external fun nativeGetVersion(): String
}
