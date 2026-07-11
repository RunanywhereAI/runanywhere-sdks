/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * QHexRT Native Bridge
 *
 * Self-contained JNI bridge for the private QHexRT (Qualcomm Hexagon NPU)
 * backend module. The native library (librac_backend_qhexrt_jni.so) exposes:
 * - rac_backend_qhexrt_register() / rac_backend_qhexrt_unregister()
 * - rac_qhexrt_probe_proto() (pre-flight Hexagon arch detection)
 * - QHexRT-owned architecture matching and device-aware model registration
 */

package com.runanywhere.sdk.npu.qhexrt

import com.runanywhere.sdk.infrastructure.logging.SDKLogger

/**
 * Native bridge for QHexRT backend registration + NPU capability probe.
 *
 * Architecture:
 * - librac_backend_qhexrt_jni.so  - QHexRT JNI (this bridge)
 * - links librac_backend_qhexrt.so - QHexRT C++ engine (QNN runtime baked in)
 * - links librac_commons.so        - commons (plugin registry + npu probe)
 */
internal object QHexRTBridge {
    private val logger = SDKLogger("QHexRT")

    @Volatile
    private var nativeLibraryLoaded = false

    private val loadLock = Any()

    /**
     * Ensure the QHexRT JNI library is loaded. librac_commons.so (via the main
     * SDK's librunanywhere_jni.so) must already be loaded so the registry +
     * npu-probe symbols resolve.
     *
     * @return true if loaded successfully, false otherwise
     */
    fun ensureNativeLibraryLoaded(): Boolean {
        if (nativeLibraryLoaded) return true

        synchronized(loadLock) {
            if (nativeLibraryLoaded) return true

            logger.info("Loading QHexRT native library...")
            try {
                System.loadLibrary("rac_backend_qhexrt_jni")
                nativeLibraryLoaded = true
                logger.info("QHexRT native library loaded successfully")
                return true
            } catch (e: UnsatisfiedLinkError) {
                logger.error("Failed to load QHexRT native library: ${e.message}", throwable = e)
                return false
            } catch (e: Exception) {
                logger.error("Unexpected error loading QHexRT native library: ${e.message}", throwable = e)
                return false
            }
        }
    }

    /** Whether the native library is loaded. */
    val isLoaded: Boolean
        get() = nativeLibraryLoaded

    // ==========================================================================
    // JNI Methods
    // ==========================================================================

    /** Register the QHexRT backend with the C++ plugin registry. 0 = success. */
    @JvmStatic
    external fun nativeRegister(): Int

    /** Unregister the QHexRT backend. 0 = success. */
    @JvmStatic
    external fun nativeUnregister(): Int

    /**
     * Pre-flight Hexagon NPU probe. Returns serialized
     * `runanywhere.v1.NpuCapability` proto bytes (decode with the generated
     * Wire adapter); empty on failure, which decodes to the all-default
     * (unknown/unsupported) capability. Works on any device (no QNN load),
     * including parts outside the validated V75/V79/V81 set.
     */
    @JvmStatic
    external fun nativeProbeNpuProto(): ByteArray

    /** True when [arch] is in QHexRT's native device-validated support set. */
    @JvmStatic
    external fun nativeArchIsSupported(arch: Int): Boolean

    /** Match a model's declared architectures against [arch] in native code. */
    @JvmStatic
    external fun nativeModelSupportsArch(
        supportedArches: IntArray,
        arch: Int,
    ): Boolean

    /**
     * Register one serialized `RegisterModelFromUrlRequest` only when the
     * current device matches [supportedArches]. A null result is the normal
     * native "not eligible on this device" outcome; native validation and
     * registry errors are raised by JNI.
     */
    @JvmStatic
    external fun nativeRegisterModelForDeviceProto(
        requestBytes: ByteArray,
        supportedArches: IntArray,
    ): ByteArray?

    /** QHexRT module version string (RAC_QHEXRT_VERSION baked into the JNI lib). */
    @JvmStatic
    external fun nativeGetVersion(): String

    /** App-private directory containing extracted QNN DSP skel libraries. */
    @JvmStatic
    external fun nativeSetSkelDirectory(path: String?)
}
