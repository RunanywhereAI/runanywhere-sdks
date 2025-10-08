package com.runanywhere.sdk.llm.llamacpp

/**
 * JVM/Android implementation for checking if llama.cpp native library is available
 */
actual fun checkNativeLibraryAvailable(): Boolean {
    return try {
        // Check if we can load the native library
        LlamaCppNative.isLoaded()
    } catch (e: Exception) {
        false
    }
}
