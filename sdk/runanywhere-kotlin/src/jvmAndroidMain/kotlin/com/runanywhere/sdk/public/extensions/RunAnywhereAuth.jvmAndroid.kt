/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for auth + device-registration state accessors.
 * Routes directly through the `rac_auth_*` and CppBridgeDevice thunks.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDevice
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere

actual fun RunAnywhere.getUserId(): String? = RunAnywhereBridge.racAuthGetUserId()

actual fun RunAnywhere.getOrganizationId(): String? = RunAnywhereBridge.racAuthGetOrganizationId()

actual val RunAnywhere.isAuthenticated: Boolean
    get() = RunAnywhereBridge.racAuthIsAuthenticated()

actual fun RunAnywhere.isDeviceRegistered(): Boolean = CppBridgeDevice.isRegistered()

actual val RunAnywhere.deviceId: String
    get() = CppBridgeDevice.getDeviceId() ?: RunAnywhereBridge.racAuthGetDeviceId() ?: ""
