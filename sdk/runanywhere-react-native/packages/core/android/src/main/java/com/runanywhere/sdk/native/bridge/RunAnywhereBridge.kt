/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * React Native HTTP-transport registration entry point.
 *
 * The JNI symbols `Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_
 * racHttpTransportRegister/UnregisterOkHttp` come from
 * librunanywhere_jni.so (built from
 * sdk/runanywhere-commons/src/jni/okhttp_transport_adapter.cpp). RN does
 * NOT compile its own copy of that adapter — the commons-jni library is
 * staged into the package's jniLibs/ and loaded below before the symbols
 * are referenced.
 *
 * Only the two transport registration thunks are exposed; the full
 * RunAnywhereBridge from sdk/runanywhere-kotlin carries many more JNI
 * bindings that RN does not need because RN talks to the C++ core through
 * its own Nitro bridges.
 */

package com.runanywhere.sdk.native.bridge

/**
 * HTTP transport registration bridge. Kept minimal — only the two
 * transport registration methods are exposed. All other RunAnywhereBridge
 * methods from the Kotlin SDK are intentionally omitted.
 */
object RunAnywhereBridge {
    /**
     * Install the OkHttp-backed platform HTTP transport. Subsequent
     * `rac_http_request_*` calls route through OkHttp instead of libcurl.
     *
     * Idempotent: subsequent calls are no-ops (guarded by the C++ adapter's
     * `globals().initialized` flag).
     *
     * @return RAC_SUCCESS on success, negative error code on failure.
     */
    @JvmStatic
    external fun racHttpTransportRegisterOkHttp(): Int

    /**
     * Uninstall the OkHttp transport; subsequent requests fall back to
     * libcurl.
     */
    @JvmStatic
    external fun racHttpTransportUnregisterOkHttp(): Int

    init {
        // librunanywhere_jni.so carries the okhttp_transport_adapter JNI
        // symbols (built from commons). The linker pulls in librac_commons.so
        // automatically because runanywhere_jni declares it as a NEEDED dep.
        System.loadLibrary("runanywhere_jni")
    }
}
