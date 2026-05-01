/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTP transport registration JNI bridge — Flutter plugin copy.
 *
 * Copy of the entry point the prebuilt `librunanywhere_jni.so` exports:
 *   Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpTransportRegisterOkHttp
 *   Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpTransportUnregisterOkHttp
 *
 * The package + class name are intentionally identical to the Kotlin SDK's
 * `RunAnywhereBridge` because JNI resolves the native methods by the full
 * Java class name. Only the two HTTP transport registration methods are
 * declared here — every other Kotlin SDK bridge method is irrelevant to the
 * Flutter plugin (which talks to the C core through Dart FFI instead).
 *
 * Loads the prebuilt `librunanywhere_jni.so` bundled under
 *   android/src/main/jniLibs/<abi>/librunanywhere_jni.so
 * which also dynamically depends on `librac_commons.so` (the transport
 * registry). Calling [racHttpTransportRegisterOkHttp] installs a vtable
 * that routes `rac_http_request_*` through [OkHttpTransport] — subsequent
 * HTTP traffic from the SDK flows through OkHttp instead of libcurl.
 */

package com.runanywhere.sdk.native.bridge

object RunAnywhereBridge {
    /**
     * Install the OkHttp-backed platform HTTP transport. Subsequent
     * `rac_http_request_*` calls route through OkHttp instead of libcurl.
     *
     * Idempotent: subsequent calls are no-ops (guarded by the C++ adapter's
     * `globals().initialized` flag).
     *
     * @return RAC_SUCCESS (0) on success, negative error code on failure.
     */
    @JvmStatic
    external fun racHttpTransportRegisterOkHttp(): Int

    /**
     * Uninstall the OkHttp transport; subsequent requests fall back to libcurl.
     */
    @JvmStatic
    external fun racHttpTransportUnregisterOkHttp(): Int

    init {
        // librunanywhere_jni.so bundles the okhttp_transport_adapter JNI bridge
        // plus a runtime dependency on librac_commons.so (the transport
        // registry).
        System.loadLibrary("runanywhere_jni")
    }
}
