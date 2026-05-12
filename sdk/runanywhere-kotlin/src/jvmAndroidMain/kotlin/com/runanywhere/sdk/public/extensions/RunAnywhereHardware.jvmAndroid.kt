/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for the hardware profile namespace.
 *
 * Wiring:
 *  - `getProfile()`            -> `rac_hardware_profile_get` via `CppBridgeHardware.getProfile()`.
 *  - `getAccelerators()`       -> TODO. Commons exposes `rac_hardware_get_accelerators`
 *                                  but no JNI thunk is bound on this branch (no commons
 *                                  C++ changes permitted by W1-16/17). Throws
 *                                  `SDKException.notImplemented`.
 *  - `setAcceleratorPreference()` -> TODO. Commons exposes
 *                                  `rac_hardware_set_accelerator_preference` but the
 *                                  JNI thunk is not yet wired (same constraint as above).
 *                                  Throws `SDKException.notImplemented`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.AcceleratorInfo
import ai.runanywhere.proto.v1.AccelerationPreference
import ai.runanywhere.proto.v1.HardwareProfileResult
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeHardware
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

actual class Hardware {
    actual fun getProfile(): HardwareProfileResult = CppBridgeHardware.getProfile()

    actual suspend fun getAccelerators(): List<AcceleratorInfo> {
        // TODO: Wire `rac_hardware_get_accelerators` once a JNI thunk
        //       (`racHardwareGetAccelerators`) is bound in
        //       sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp.
        //       Until then the Kotlin surface matches Swift's "not supported"
        //       fallback behaviour (rac_result_t == RAC_ERROR_NOT_SUPPORTED).
        throw SDKException.notImplemented("Hardware.getAccelerators")
    }

    actual suspend fun setAcceleratorPreference(pref: AccelerationPreference) {
        // TODO: Wire `rac_hardware_set_accelerator_preference(pref.value)`
        //       once a JNI thunk (`racHardwareSetAcceleratorPreference`) is
        //       bound in
        //       sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp.
        //       Until then the Kotlin surface matches Swift's "not supported"
        //       fallback behaviour (rac_result_t == RAC_ERROR_NOT_SUPPORTED).
        throw SDKException.notImplemented("Hardware.setAcceleratorPreference")
    }
}

private val hardwareInstance = Hardware()

actual val RunAnywhere.hardware: Hardware
    get() = hardwareInstance
