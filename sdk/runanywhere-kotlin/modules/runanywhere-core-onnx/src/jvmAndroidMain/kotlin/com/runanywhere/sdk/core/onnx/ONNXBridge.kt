/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * ONNX Native Bridge
 *
 * Self-contained JNI bridge for the ONNX backend module.
 * This mirrors the Swift ONNXBackend XCFramework architecture.
 *
 * The native library (librac_backend_onnx_jni.so) contains:
 * - rac_backend_onnx_register()
 * - rac_backend_onnx_unregister()
 */

package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Native bridge for ONNX backend registration.
 *
 * This object handles loading the ONNX-specific JNI library and provides
 * JNI methods for backend registration with the C++ service registry.
 *
 * Architecture:
 * - librac_backend_onnx_jni.so - ONNX JNI (this bridge)
 * - Links to librac_backend_onnx.so - ONNX C++ backend (STT, TTS, VAD)
 * - Links to librac_commons.so - Commons library with service registry
 */
internal object ONNXBridge {

    private const val TAG = "ONNXBridge"
    private val logger = SDKLogger(TAG)

    @Volatile
    private var nativeLibraryLoaded = false

    private val loadLock = Any()

    /**
     * Ensure the ONNX JNI library is loaded.
     *
     * Loads librac_backend_onnx_jni.so and its dependencies:
     * - librac_backend_onnx.so (ONNX C++ backend)
     * - librac_commons.so (commons library - must be loaded first)
     * - libonnxruntime.so
     * - libsherpa-onnx-c-api.so
     *
     * @return true if loaded successfully, false otherwise
     */
    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true

        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true

            logger.info("Loading ONNX native library...")

            try {
                // The main SDK's librunanywhere_jni.so must be loaded first
                // (provides librac_commons.so with service registry).
                // The ONNX JNI provides backend registration functions.
                System.loadLibrary("rac_backend_onnx_jni")
                nativeLibraryLoaded = true
                logger.info("✅ ONNX native library loaded successfully")
                return true
            } catch (e: UnsatisfiedLinkError) {
                logger.error("❌ Failed to load ONNX native library: ${e.message}", e)
                return false
            } catch (e: Exception) {
                logger.error("❌ Unexpected error loading ONNX native library: ${e.message}", e)
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
     * Register the ONNX backend with the C++ service registry.
     * This registers all ONNX services: STT, TTS, VAD.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeRegister(): Int

    /**
     * Unregister the ONNX backend from the C++ service registry.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeUnregister(): Int

    /**
     * Check if the ONNX backend is registered.
     *
     * @return true if registered
     */
    @JvmStatic
    external fun nativeIsRegistered(): Boolean

    /**
     * Get the ONNX Runtime library version.
     *
     * @return Version string
     */
    @JvmStatic
    external fun nativeGetVersion(): String
}
