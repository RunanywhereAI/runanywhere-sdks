package com.runanywhere.sdk.llm.mlc

/**
 * Check if MLC-LLM native library is available on Android
 *
 * Attempts to load the TVM runtime library that is required for MLC-LLM execution.
 * The library (libtvm4j_runtime_packed.so) must be present in the jniLibs directory.
 *
 * @return true if the native library loads successfully, false otherwise
 */
actual fun checkNativeLibraryAvailable(): Boolean {
    return try {
        // Attempt to load the TVM runtime library
        // This is the core native library required for MLC-LLM
        System.loadLibrary("tvm4j_runtime_packed")
        true
    } catch (e: UnsatisfiedLinkError) {
        // Library not found or couldn't be loaded
        false
    } catch (e: Exception) {
        // Any other error during library loading
        false
    }
}
