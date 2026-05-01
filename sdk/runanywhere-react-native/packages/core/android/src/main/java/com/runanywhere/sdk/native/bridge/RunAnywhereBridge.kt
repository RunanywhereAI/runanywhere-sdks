/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * React Native copy of the Kotlin SDK's RunAnywhereBridge HTTP transport
 * registration entry point (v2 close-out Phase H6).
 *
 * Only the HTTP transport registration methods are replicated here — the
 * full `RunAnywhereBridge` from sdk/runanywhere-kotlin carries many more
 * JNI bindings that RN does not need, because RN talks to the C++ core
 * through its own Nitro bridges.
 *
 * The package + class name are intentionally identical to the Kotlin SDK
 * copy because `okhttp_transport_adapter.cpp` exports its JNI symbols
 * under this fully-qualified Java name:
 *
 *   Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpTransportRegisterOkHttp
 *
 * RN's CMakeLists pulls the same `okhttp_transport_adapter.cpp` into
 * `librunanywherecore.so`, so the symbol lookup resolves against RN's
 * own native library rather than a Kotlin-SDK-provided one.
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
        // librunanywherecore.so bundles:
        //   - okhttp_transport_adapter.cpp (the JNI bridge)
        //   - librac_commons.so dependency (the transport registry)
        System.loadLibrary("runanywherecore")
    }
}
