/*
  * Copyright 2026 RunAnywhere SDK
  * SPDX-License-Identifier: Apache-2.0
  *
  * Cross-SDK contract for the host device state the hybrid router needs
  * to evaluate NETWORK / Battery filters. Each SDK binding (Kotlin,
  * Swift, Flutter, RN, Web) ships its own implementation and registers
  * one instance via [RACRouter.setDeviceStateProvider] at app init.
  *
  * Native side: registration crosses into commons through the JNI thunk
  * `racHybridSetDeviceState`, which wires this Kotlin object into the
  * `rac_hybrid_device_state_ops_t` vtable in commons. The C router then
  * calls back into these methods on every generate() to fill the routing
  * context.
  *
  * Method names MUST match what the JNI thunk looks up via `GetMethodID`
  * in sdk/runanywhere-commons/src/jni/rac_hybrid_router_jni.cpp — do NOT
  * rename without also updating the C++ side.
  */

package com.runanywhere.sdk.public.hybrid

interface DeviceStateProvider {
    /** True iff the host has a usable internet connection right now. */
    fun isOnline(): Boolean

    /** Battery level in [0, 100]; 100 on hosts without a battery. */
    fun batteryPercent(): Int

    /** True when the device is currently thermally throttled. */
    fun isThermalThrottled(): Boolean
}