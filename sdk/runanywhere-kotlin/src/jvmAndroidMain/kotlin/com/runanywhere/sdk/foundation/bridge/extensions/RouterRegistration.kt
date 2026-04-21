/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Glue between Kotlin model lifecycle and the C++ hybrid router.
 *
 * The router lives in runanywhere-commons and selects one STT backend per
 * request via eligibility + policy + confidence cascade. Each registered
 * backend is a long-lived rac_stt_component with a loaded model. This
 * object owns the Sarvam component handle (cloud, lifetime tied to
 * Sarvam.register) and tracks the local component's registration so that
 * model swaps and shutdown leave the router consistent.
 *
 * No routing decisions live in Kotlin. We only register/unregister.
 */
package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

object RouterRegistration {

    private val logger = SDKLogger("RouterRegistration")
    private val lock = Any()

    // Local model: re-registered on every loadModel(); unregistered on unload().
    const val LOCAL_MODULE_ID = "local-stt"

    // Cloud model: registered once when Sarvam.register() succeeds.
    const val SARVAM_MODULE_ID = "sarvam-cloud"
    const val SARVAM_MODEL_PATH = "sarvam:saarika:v2.5"

    // Owned exclusively by RouterRegistration — separate from CppBridgeSTT's
    // component handle so the local user-picker model and Sarvam can be
    // alive concurrently and the router can pick between them per request.
    @Volatile private var sarvamComponentHandle: Long = 0L
    @Volatile private var localRegistered: Boolean = false

    /**
     * Register the currently-loaded local STT component with the router.
     *
     * Called from [CppBridgeSTT.loadModel] after a successful native load.
     * The component handle is the one CppBridgeSTT owns — non-owning for
     * the router. Subsequent calls re-register (used by model swap).
     */
    fun registerLocal(componentHandle: Long, modelName: String) {
        if (componentHandle == 0L) return
        synchronized(lock) {
            if (localRegistered) {
                RunAnywhereBridge.racRouterUnregisterStt(LOCAL_MODULE_ID)
                localRegistered = false
            }
            val rc = RunAnywhereBridge.racRouterRegisterStt(
                componentHandle = componentHandle,
                moduleId = LOCAL_MODULE_ID,
                moduleName = modelName,
                priority = 100,
                isLocalOnly = true,
                needsNetwork = false,
                costCentsPerMinute = 0.0f,
                inferenceFramework = "onnx",
            )
            if (rc != 0) {
                logger.warn("registerLocal('$modelName') failed: rc=$rc")
                return
            }
            localRegistered = true
            logger.info("registerLocal('$modelName') OK — router has ${RunAnywhereBridge.racRouterSttCount()} STT backend(s)")
        }
    }

    /**
     * Unregister the local STT component. Called from [CppBridgeSTT.unload]
     * BEFORE the native unload (the router holds a non-owning service ptr
     * that would dangle otherwise).
     */
    fun unregisterLocal() {
        synchronized(lock) {
            if (!localRegistered) return
            RunAnywhereBridge.racRouterUnregisterStt(LOCAL_MODULE_ID)
            localRegistered = false
            logger.info("unregisterLocal OK — router has ${RunAnywhereBridge.racRouterSttCount()} STT backend(s)")
        }
    }

    /**
     * Create a dedicated STT component for Sarvam and register it.
     *
     * Called from [com.runanywhere.sdk.cloud.sarvam.Sarvam.register] after
     * the Sarvam service provider is registered with the C registry. The
     * "model load" is a no-op for the cloud backend (just sets the model
     * id used by the service factory).
     */
    fun registerSarvam(): Boolean {
        synchronized(lock) {
            if (sarvamComponentHandle != 0L) {
                logger.debug("Sarvam already registered with router")
                return true
            }
            val handle = RunAnywhereBridge.racSttComponentCreate()
            if (handle == 0L) {
                logger.error("racSttComponentCreate failed for Sarvam")
                return false
            }
            val loadRc = RunAnywhereBridge.racSttComponentLoadModel(
                handle, SARVAM_MODEL_PATH, SARVAM_MODEL_PATH, "Sarvam Saarika v2.5",
            )
            if (loadRc != 0) {
                logger.error("racSttComponentLoadModel(sarvam) failed: rc=$loadRc")
                RunAnywhereBridge.racSttComponentDestroy(handle)
                return false
            }
            val regRc = RunAnywhereBridge.racRouterRegisterStt(
                componentHandle = handle,
                moduleId = SARVAM_MODULE_ID,
                moduleName = "Sarvam AI (Cloud)",
                priority = 80,
                isLocalOnly = false,
                needsNetwork = true,
                costCentsPerMinute = 2.5f,
                inferenceFramework = "sarvam",
            )
            if (regRc != 0) {
                logger.error("racRouterRegisterStt(sarvam) failed: rc=$regRc")
                RunAnywhereBridge.racSttComponentUnload(handle)
                RunAnywhereBridge.racSttComponentDestroy(handle)
                return false
            }
            sarvamComponentHandle = handle
            logger.info("registerSarvam OK — router has ${RunAnywhereBridge.racRouterSttCount()} STT backend(s)")
            return true
        }
    }

    fun unregisterSarvam() {
        synchronized(lock) {
            val h = sarvamComponentHandle
            if (h == 0L) return
            RunAnywhereBridge.racRouterUnregisterStt(SARVAM_MODULE_ID)
            RunAnywhereBridge.racSttComponentUnload(h)
            RunAnywhereBridge.racSttComponentDestroy(h)
            sarvamComponentHandle = 0L
            logger.info("unregisterSarvam OK")
        }
    }

    fun shutdown() {
        unregisterLocal()
        unregisterSarvam()
    }
}
