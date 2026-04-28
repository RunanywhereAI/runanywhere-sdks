/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * SDK-internal glue between Kotlin model lifecycle and the C++ hybrid router.
 *
 * Owns the SDK-wide global [HybridRouter] instance for STT and proxies the
 * (now-internal) lifecycle hooks called from CppBridgeSTT, Sarvam, and
 * PlatformBridge. Public dev code should use [HybridRouter] directly from
 * `com.runanywhere.sdk.public.routing` instead of these helpers.
 */
package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.routing.BackendDescriptor
import com.runanywhere.sdk.public.routing.Capability
import com.runanywhere.sdk.public.routing.HybridRouter

object RouterRegistration {

    private val logger = SDKLogger("RouterRegistration")
    private val lock = Any()

    const val LOCAL_MODULE_ID = "local-stt"
    const val SARVAM_MODULE_ID = "sarvam-cloud"
    const val SARVAM_MODEL_PATH = "sarvam:saarika:v2.5"

    // SDK-wide STT router. Lazily created; survives until [shutdown].
    @Volatile private var globalSttRouter: HybridRouter? = null

    @Volatile private var sarvamComponentHandle: Long = 0L
    @Volatile private var localRegistered: Boolean = false

    /** Lazily get-or-create the SDK-wide STT router. Internal use. */
    internal fun sttRouter(): HybridRouter {
        globalSttRouter?.let { return it }
        return synchronized(lock) {
            globalSttRouter ?: HybridRouter(Capability.STT).also { globalSttRouter = it }
        }
    }

    /** Register the currently-loaded local STT component with the router. */
    fun registerLocal(componentHandle: Long, modelName: String) {
        if (componentHandle == 0L) return
        synchronized(lock) {
            val router = sttRouter()
            if (localRegistered) {
                router.unregister(LOCAL_MODULE_ID)
                localRegistered = false
            }
            val ok = router.registerStt(
                componentHandle = componentHandle,
                descriptor = BackendDescriptor(
                    moduleId = LOCAL_MODULE_ID,
                    moduleName = modelName,
                    capability = Capability.STT,
                    basePriority = 100,
                    isLocalOnly = true,
                    needsNetwork = false,
                    costCentsPerMinute = 0.0f,
                    inferenceFramework = "onnx",
                ),
            )
            if (!ok) {
                logger.warn("registerLocal('$modelName') failed")
                return
            }
            localRegistered = true
            logger.info("registerLocal('$modelName') OK — router has ${router.count()} STT backend(s)")
        }
    }

    fun unregisterLocal() {
        synchronized(lock) {
            if (!localRegistered) return
            sttRouter().unregister(LOCAL_MODULE_ID)
            localRegistered = false
            logger.info("unregisterLocal OK — router has ${sttRouter().count()} STT backend(s)")
        }
    }

    /** Create a dedicated STT component for Sarvam and register it. */
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
            val ok = sttRouter().registerStt(
                componentHandle = handle,
                descriptor = BackendDescriptor(
                    moduleId = SARVAM_MODULE_ID,
                    moduleName = "Sarvam AI (Cloud)",
                    capability = Capability.STT,
                    basePriority = 80,
                    isLocalOnly = false,
                    needsNetwork = true,
                    costCentsPerMinute = 2.5f,
                    inferenceFramework = "sarvam",
                ),
            )
            if (!ok) {
                RunAnywhereBridge.racSttComponentUnload(handle)
                RunAnywhereBridge.racSttComponentDestroy(handle)
                return false
            }
            sarvamComponentHandle = handle
            logger.info("registerSarvam OK — router has ${sttRouter().count()} STT backend(s)")
            return true
        }
    }

    fun unregisterSarvam() {
        synchronized(lock) {
            val h = sarvamComponentHandle
            if (h == 0L) return
            sttRouter().unregister(SARVAM_MODULE_ID)
            RunAnywhereBridge.racSttComponentUnload(h)
            RunAnywhereBridge.racSttComponentDestroy(h)
            sarvamComponentHandle = 0L
            logger.info("unregisterSarvam OK")
        }
    }

    fun shutdown() {
        synchronized(lock) {
            unregisterLocal()
            unregisterSarvam()
            globalSttRouter?.close()
            globalSttRouter = null
        }
    }
}
