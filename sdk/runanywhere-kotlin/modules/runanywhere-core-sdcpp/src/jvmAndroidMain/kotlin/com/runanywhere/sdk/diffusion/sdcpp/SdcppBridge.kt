package com.runanywhere.sdk.diffusion.sdcpp

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Native bridge for sd.cpp backend registration.
 *
 * Loads librac_backend_sdcpp_jni.so and provides JNI methods
 * for registering the sd.cpp diffusion backend with the C++ service registry.
 */
internal object SdcppBridge {
    private val logger = SDKLogger("SdcppBridge")

    @Volatile
    private var nativeLibraryLoaded = false

    private val loadLock = Any()

    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true

        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true

            logger.info("Loading sd.cpp native library...")

            try {
                System.loadLibrary("rac_backend_sdcpp_jni")
                nativeLibraryLoaded = true
                logger.info("sd.cpp native library loaded successfully")
                return true
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load sd.cpp native library: ${e.message}", throwable = e)
                return false
            } catch (e: Exception) {
                logger.error("Unexpected error loading sd.cpp native library: ${e.message}", throwable = e)
                return false
            }
        }
    }

    val isLoaded: Boolean
        get() = nativeLibraryLoaded

    @JvmStatic
    external fun nativeRegister(): Int
}
