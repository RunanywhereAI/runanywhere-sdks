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
    private val logger = SDKLogger.onnx

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
                logger.info("ONNX native library loaded successfully")
                return true
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load ONNX native library: ${e.message}", throwable = e)
                return false
            } catch (e: Exception) {
                logger.error("Unexpected error loading ONNX native library: ${e.message}", throwable = e)
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

    // ==========================================================================
    // NPU Detection (for diagnostics/logging only)
    // ==========================================================================

    /**
     * Check if NPU acceleration is available on this device.
     * This is for diagnostic purposes - the SDK automatically uses NPU when available.
     *
     * @return true if NPU hardware acceleration is available
     */
    @JvmStatic
    external fun nativeIsNPUAvailable(): Boolean

    /**
     * Get NPU device information as JSON string (for diagnostics).
     *
     * @return JSON string with NPU hardware info
     */
    @JvmStatic
    external fun nativeGetNPUInfo(): String

    // ==========================================================================
    // Internal NPU Methods - Used by ONNX backend, not exposed to SDK users
    // ==========================================================================

    @JvmStatic
    internal external fun nativeCreateTTSHybrid(
        encoderPath: String,
        vocoderPath: String,
        perfMode: Int,
        vtcmMb: Int,
        enableContextCache: Boolean
    ): Long

    @JvmStatic
    internal external fun nativeGetNPUStats(handle: Long): String

    @JvmStatic
    internal external fun nativeValidateModelForNPU(modelPath: String): String

    // ==========================================================================
    // Kokoro NPU Benchmark APIs
    // ==========================================================================

    /**
     * Run NPU vs CPU benchmark on Kokoro TTS model.
     *
     * This method runs the same text synthesis through both NPU (NNAPI) and
     * CPU-only execution paths and returns a JSON string with comparison results.
     *
     * @param handle TTS handle (must be a Kokoro model)
     * @param testText Optional test text (null for default benchmark text)
     * @return JSON string with benchmark results including:
     *         - npu_inference_ms: NPU inference time
     *         - cpu_inference_ms: CPU inference time
     *         - speedup: CPU time / NPU time (> 1 means NPU is faster)
     *         - npu_available: Whether NNAPI NPU is active
     *         - success: Whether benchmark completed successfully
     */
    @JvmStatic
    external fun nativeRunKokoroBenchmark(handle: Long, testText: String?): String

    /**
     * Check if a TTS handle is a Kokoro model.
     *
     * @param handle TTS handle
     * @return true if the handle points to a Kokoro TTS model
     */
    @JvmStatic
    external fun nativeIsKokoroTTS(handle: Long): Boolean

    /**
     * Check if NNAPI NPU acceleration is active for a Kokoro TTS model.
     *
     * @param handle TTS handle (must be a Kokoro model)
     * @return true if NPU is active
     */
    @JvmStatic
    external fun nativeIsKokoroNPUActive(handle: Long): Boolean

    /**
     * Run standalone Kokoro NPU vs CPU benchmark.
     *
     * This creates a temporary Kokoro TTS loader, runs the benchmark, and cleans up.
     * Does NOT require an existing TTS handle - useful for testing NPU acceleration
     * before a model is loaded in the main app.
     *
     * @param modelPath Path to Kokoro model directory
     * @param testText Optional test text (null for default benchmark text)
     * @return JSON string with benchmark results including:
     *         - npu_inference_ms: NPU/NNAPI inference time
     *         - cpu_inference_ms: CPU-only inference time
     *         - speedup: CPU time / NPU time (> 1 means NPU is faster)
     *         - npu_available: Whether NNAPI NPU is active
     *         - npu_is_faster: Boolean indicating if NPU is faster
     *         - audio_duration_ms: Duration of generated audio
     *         - npu_rtf / cpu_rtf: Real-time factors
     *         - success: Whether benchmark completed successfully
     */
    @JvmStatic
    external fun nativeRunStandaloneKokoroBenchmark(modelPath: String, testText: String?): String
}
