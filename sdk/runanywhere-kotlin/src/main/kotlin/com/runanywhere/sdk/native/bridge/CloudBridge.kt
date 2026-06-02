/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JNI bridge for the cloud-STT backend PLUGIN.
 *
 * cloud is a real engine plugin (mirrors onnx / llamacpp): these native
 * methods register the "cloud" engine with the unified plugin registry so
 * it is routable via `rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE,
 * hint="cloud")`. The concrete HTTP provider (e.g. "sarvam") is carried
 * in the create config (config_json["provider"]), not as a distinct engine.
 * Service creation no longer goes through a bespoke per-engine factory — the
 * hybrid router creates the online side via
 * `RunAnywhereBridge.racSttHybridRouterCreateService("cloud", …)` which
 * resolves the routed engine's `stt_ops->create` exactly like the offline
 * (sherpa) side.
 *
 * The cloud JNI TU is linked into the commons JNI shared library
 * (librunanywhere_jni.so), so loading the commons library via
 * [RunAnywhereBridge.ensureNativeLibraryLoaded] also resolves these symbols —
 * no separate System.loadLibrary is required.
 */

package com.runanywhere.sdk.native.bridge

/**
 * Native plugin-registration entry points for the cloud-STT engine.
 *
 * The quartet below maps to the symbols emitted by
 * `RAC_DEFINE_ENGINE_JNI_BRIDGE_NO_ONLOAD(com_runanywhere_sdk_native_bridge_CloudBridge,
 * rac_backend_cloud_register, …)` in
 * `engines/cloud/jni/rac_cloud_jni.cpp`. Public callers register cloud
 * provider credentials + fire this registration via
 * [com.runanywhere.sdk.public.hybrid.BACKEND.CLOUD.register].
 */
object CloudBridge {
    init {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
    }

    /**
     * Register the "cloud" engine with the C++ plugin registry so the
     * hybrid router can route TRANSCRIBE requests to it (hint = "cloud").
     * Tolerant of double-registration on the native side.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure.
     */
    @JvmStatic external fun nativeRegister(): Int

    /**
     * Unregister the "cloud" engine from the C++ plugin registry.
     *
     * @return 0 (RAC_SUCCESS) on success, error code on failure.
     */
    @JvmStatic external fun nativeUnregister(): Int

    /** Whether the "cloud" plugin is currently registered for TRANSCRIBE. */
    @JvmStatic external fun nativeIsRegistered(): Boolean

    /** Native build/version string reported by the cloud JNI bridge. */
    @JvmStatic external fun nativeGetVersion(): String
}
