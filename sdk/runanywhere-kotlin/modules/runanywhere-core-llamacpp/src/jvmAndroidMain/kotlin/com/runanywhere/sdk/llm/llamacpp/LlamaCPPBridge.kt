/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * LlamaCPP Native Bridge
 *
 * Self-contained JNI bridge for the LlamaCPP backend module.
 * This mirrors the Swift LlamaCPPBackend XCFramework architecture.
 *
 * The native library (librunanywhere_llamacpp.so) contains LLM inference capabilities.
 */

package com.runanywhere.sdk.llm.llamacpp

import android.util.Log

/**
 * Native bridge for LlamaCPP backend registration.
 *
 * This object handles loading the LlamaCPP-specific JNI library and provides
 * JNI methods for backend registration with the C++ service registry.
 *
 * Architecture:
 * - librunanywhere_llamacpp.so - LlamaCPP backend with JNI
 * - Links to librunanywhere_jni.so - Main JNI bridge
 * - Links to libc++_shared.so, libomp.so - Runtime dependencies
 */
internal object LlamaCPPBridge {

    private const val TAG = "LlamaCPPBridge"

    @Volatile
    private var nativeLibraryLoaded = false

    private val loadLock = Any()

    /**
     * Ensure the LlamaCPP JNI library is loaded.
     *
     * Loads librunanywhere_llamacpp.so and its dependencies:
     * - librunanywhere_jni.so (main JNI bridge - must be loaded first)
     * - libc++_shared.so, libomp.so (runtime dependencies)
     *
     * @return true if loaded successfully, false otherwise
     */
    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true

        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true

            Log.i(TAG, "Loading LlamaCPP native library...")

            try {
                // Load the LlamaCPP backend library first (contains the LLM implementation)
                System.loadLibrary("runanywhere_llamacpp")
                Log.i(TAG, "✅ runanywhere_llamacpp loaded")
                
                // Load the JNI bridge which contains nativeRegister, nativeGenerate, etc.
                System.loadLibrary("rac_backend_llamacpp_jni")
                nativeLibraryLoaded = true
                Log.i(TAG, "✅ LlamaCPP JNI bridge loaded successfully")
                return true
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "❌ Failed to load LlamaCPP native library: ${e.message}", e)
                return false
            } catch (e: Exception) {
                Log.e(TAG, "❌ Unexpected error loading LlamaCPP native library: ${e.message}", e)
                return false
            }
        }
    }

    /**
     * Check if the native library is loaded.
     */
    val isLoaded: Boolean
        get() = nativeLibraryLoaded

    // ==========================================================================
    // JNI Methods
    // ==========================================================================

    /**
     * Register the LlamaCPP backend with the C++ service registry.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeRegister(): Int

    /**
     * Unregister the LlamaCPP backend from the C++ service registry.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeUnregister(): Int

    /**
     * Check if the LlamaCPP backend is registered.
     *
     * @return true if registered
     */
    @JvmStatic
    external fun nativeIsRegistered(): Boolean

    /**
     * Get the llama.cpp library version.
     *
     * @return Version string
     */
    @JvmStatic
    external fun nativeGetVersion(): String
}
