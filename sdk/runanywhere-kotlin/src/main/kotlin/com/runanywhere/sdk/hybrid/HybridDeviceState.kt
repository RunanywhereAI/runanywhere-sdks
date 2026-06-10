/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Kotlin binding for the cross-SDK host device-state vtable
 * (rac_hybrid_device_state.h). The hybrid router consults this vtable on
 * every transcribe() to evaluate the Network / Battery hard filters; it is
 * NOT passed in the per-request routing context.
 *
 * All routing LOGIC stays in commons — this file only installs the host
 * callbacks (isOnline / batteryPercent / isThermalThrottled) through the JNI
 * thunk `racHybridSetDeviceState`, which wires the Kotlin provider into the
 * `rac_hybrid_device_state_ops_t` vtable in commons.
 *
 * Mirrors Swift's HybridDeviceState.swift (HybridDeviceStateProvider protocol
 * + HybridDeviceState.setProvider/clear).
 */

package com.runanywhere.sdk.hybrid

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Host-supplied source of the device state the hybrid router needs.
 *
 * Implementations MUST be thread-safe / reentrant: commons may invoke these
 * from multiple request threads concurrently (see the warning in
 * rac_hybrid_device_state.h).
 *
 * Method names MUST match what the JNI thunk looks up via `GetMethodID`
 * (`isOnline()Z`, `batteryPercent()I`, `isThermalThrottled()Z`) in
 * sdk/runanywhere-commons/src/jni/rac_hybrid_device_state_jni.cpp — do NOT
 * rename without also updating the C++ side.
 */
interface HybridDeviceStateProvider {
    /** True iff the host has a usable internet connection right now. */
    fun isOnline(): Boolean

    /** Battery level in `[0, 100]`; return 100 on hosts without a battery. */
    fun batteryPercent(): Int

    /** True when the device is currently thermally throttled. */
    fun isThermalThrottled(): Boolean
}

/**
 * Installs / clears the device-state vtable in commons.
 *
 * Exactly one provider is active process-wide (the C ABI holds a single
 * vtable). Re-registering replaces the previous provider. Mirrors Swift's
 * `HybridDeviceState` enum.
 */
object HybridDeviceState {
    private val logger = SDKLogger("Hybrid.DeviceState")

    /**
     * Register [provider] as the host device-state source the router consults
     * on every transcribe. Pass `null` to unregister and fall back to the
     * commons optimistic default (always-online, 100% battery, not-throttled).
     *
     * Typical Android wiring (call once after SDK init):
     *
     *     HybridDeviceState.setProvider(AndroidDeviceStateProvider(applicationContext))
     *
     * Thread-safe; the native vtable swap is atomic.
     *
     * @return `true` when the vtable was installed (or cleared) successfully.
     */
    @JvmStatic
    fun setProvider(provider: HybridDeviceStateProvider?): Boolean {
        if (provider == null) {
            return clear()
        }
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        val rc = RunAnywhereBridge.racHybridSetDeviceState(provider)
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            logger.error("racHybridSetDeviceState failed: rc=$rc")
            return false
        }
        return true
    }

    /**
     * Detach the host provider and restore the commons default vtable.
     *
     * @return `true` when the default vtable was restored successfully.
     */
    @JvmStatic
    fun clear(): Boolean {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        val rc = RunAnywhereBridge.racHybridSetDeviceState(null)
        if (rc != RunAnywhereBridge.RAC_SUCCESS) {
            logger.error("racHybridSetDeviceState(null) failed: rc=$rc")
            return false
        }
        return true
    }
}
