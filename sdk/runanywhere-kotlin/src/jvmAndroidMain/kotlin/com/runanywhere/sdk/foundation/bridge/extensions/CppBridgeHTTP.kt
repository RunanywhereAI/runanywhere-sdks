/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTP bridge extension — thin facade over [OkHttpHttpTransport].
 *
 * Mirrors the Swift `CppBridge+HTTP.swift` (49 LOC) facade: every actual
 * network call lives in the transport implementation
 * (`httptransport/OkHttpHttpTransport.kt`); this file exists only so the
 * historical `CppBridgeHTTP.*` call sites keep compiling while the C++
 * JNI bridge is retargeted at the new package path.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.httptransport.OkHttpHttpTransport
import okhttp3.OkHttpClient

/**
 * HTTP bridge — thin wrapper over [OkHttpHttpTransport].
 *
 * Kept as a `object` namespace (parity with Swift's `CppBridge.HTTP`
 * enum). All real work delegates to [OkHttpHttpTransport]; the
 * transport vtable, JNI entry points, and DTOs live there.
 */
object CppBridgeHTTP {
    /** Install the OkHttp HTTP transport. Delegates to [OkHttpHttpTransport.register]. */
    @JvmStatic
    fun register(): Boolean = OkHttpHttpTransport.register()

    /** Uninstall the OkHttp HTTP transport. Delegates to [OkHttpHttpTransport.unregister]. */
    @JvmStatic
    fun unregister() = OkHttpHttpTransport.unregister()

    /** Install a custom [OkHttpClient]. Delegates to [OkHttpHttpTransport.setHttpClient]. */
    @JvmStatic
    fun setHttpClient(client: OkHttpClient?) = OkHttpHttpTransport.setHttpClient(client)

    /** Returns the currently installed custom client, or null if using default. */
    @JvmStatic
    fun getHttpClient(): OkHttpClient? = OkHttpHttpTransport.getHttpClient()
}
