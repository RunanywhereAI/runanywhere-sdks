package com.runanywhere.sdk.llm.llamacpp

/**
 * Platform-specific implementation to check native library availability
 */
actual fun checkNativeLibraryAvailable(): Boolean {
    return try {
        System.loadLibrary("llama-jni")
        true
    } catch (e: UnsatisfiedLinkError) {
        // Library not available
        false
    } catch (e: SecurityException) {
        // Permission denied
        false
    }
}
