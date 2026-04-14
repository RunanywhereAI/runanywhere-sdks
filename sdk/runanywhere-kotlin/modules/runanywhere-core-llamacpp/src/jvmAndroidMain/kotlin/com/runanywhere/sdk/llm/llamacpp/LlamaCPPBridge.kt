/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * LlamaCPP Native Bridge
 *
 * Self-contained JNI bridge for the LlamaCPP backend module.
 * This mirrors the Swift LlamaCPPBackend XCFramework architecture.
 *
 * The native library (librac_backend_llamacpp_jni.so) contains:
 * - rac_backend_llamacpp_register()
 * - rac_backend_llamacpp_unregister()
 */

package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Native bridge for LlamaCPP backend registration.
 *
 * This object handles loading the LlamaCPP-specific JNI library and provides
 * JNI methods for backend registration with the C++ service registry.
 *
 * Architecture:
 * - librac_backend_llamacpp_jni.so - LlamaCPP JNI (this bridge)
 * - Links to librac_backend_llamacpp.so - LlamaCPP C++ backend
 * - Links to librac_commons.so - Commons library with service registry
 */
internal object LlamaCPPBridge {
    private val logger = SDKLogger.llamacpp

    @Volatile
    private var nativeLibraryLoaded = false

    private val loadLock = Any()

    /**
     * Ensure the LlamaCPP JNI library is loaded.
     *
     * Loads librac_backend_llamacpp_jni.so and its dependencies:
     * - librac_backend_llamacpp.so (LlamaCPP C++ backend)
     * - librac_commons.so (commons library - must be loaded first)
     * - librunanywhere_llamacpp.so (from runanywhere-core)
     *
     * @return true if loaded successfully, false otherwise
     */
    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true

        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true

            logger.info("Loading LlamaCPP native library...")

            try {
                // The main SDK's librunanywhere_jni.so must be loaded first
                // (provides librac_commons.so with service registry).
                // The LlamaCPP JNI provides backend registration functions.
                System.loadLibrary("rac_backend_llamacpp_jni")
                nativeLibraryLoaded = true
                logger.info("LlamaCPP native library loaded successfully")
                return true
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load LlamaCPP native library: ${e.message}", throwable = e)
                return false
            } catch (e: Exception) {
                logger.error("Unexpected error loading LlamaCPP native library: ${e.message}", throwable = e)
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

    // ==========================================================================
    // LLM Direct Operations
    // ==========================================================================

    /**
     * Create a LlamaCPP instance and load a model.
     *
     * @param modelPath Path to the GGUF model file
     * @param contextSize Context window size
     * @param numThreads Number of inference threads
     * @param gpuLayers Number of layers to offload to GPU
     * @return Native handle (0 on failure)
     */
    @JvmStatic
    external fun nativeCreate(modelPath: String, contextSize: Int, numThreads: Int, gpuLayers: Int): Long

    /**
     * Destroy a LlamaCPP instance.
     */
    @JvmStatic
    external fun nativeDestroy(handle: Long)

    /**
     * Generate text (blocking).
     *
     * @param handle Native handle
     * @param prompt Input prompt
     * @param maxTokens Max tokens to generate
     * @param temperature Sampling temperature
     * @param grammar GBNF grammar string for constrained decoding (null for unconstrained)
     * @return Generated text or null on failure
     */
    @JvmStatic
    external fun nativeGenerate(handle: Long, prompt: String, maxTokens: Int, temperature: Float, grammar: String?): String?

    /**
     * Convert a JSON Schema to a GBNF grammar string.
     *
     * @param handle Native handle
     * @param jsonSchema JSON Schema string
     * @return GBNF grammar string or null on failure
     */
    @JvmStatic
    external fun nativeJsonSchemaToGrammar(handle: Long, jsonSchema: String): String?

    /**
     * Cancel ongoing generation.
     */
    @JvmStatic
    external fun nativeCancel(handle: Long)

    /**
     * Get model info as JSON.
     */
    @JvmStatic
    external fun nativeGetModelInfo(handle: Long): String?

    // ==========================================================================
    // VLM Registration JNI Methods
    // ==========================================================================

    /**
     * Register the LlamaCPP VLM backend with the C++ service registry.
     * Mirrors iOS LlamaCPP.registerVLM() pattern.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeRegisterVlm(): Int

    /**
     * Unregister the LlamaCPP VLM backend from the C++ service registry.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure
     */
    @JvmStatic
    external fun nativeUnregisterVlm(): Int
}
