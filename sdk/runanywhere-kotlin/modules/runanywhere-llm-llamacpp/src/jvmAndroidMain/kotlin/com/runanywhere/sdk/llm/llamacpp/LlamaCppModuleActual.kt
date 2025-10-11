package com.runanywhere.sdk.llm.llamacpp

/**
 * JVM/Android implementation for checking if llama.cpp native library is available
 */
actual fun checkNativeLibraryAvailable(): Boolean {
    return try {
        // Check if llama-android library can be loaded
        LLamaAndroid.instance().isLoaded
    } catch (e: Exception) {
        false
    }
}
