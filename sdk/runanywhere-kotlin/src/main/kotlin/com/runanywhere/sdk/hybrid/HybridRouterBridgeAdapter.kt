/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Builds a native rac_stt_service_t handle (a Long) for a given
 * HybridModel, and tears it down again on close().
 *
 * BOTH sides are created through the SAME unified registry-routed factory
 * (`rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, hint=<engine>)` →
 * `stt_ops->create`). There is no bespoke per-engine factory on the router
 * path:
 *   - SHERPA — engine hint "sherpa", on-device model path resolved through
 *     the C model registry ([RunAnywhereBridge.racSttServiceCreate], which
 *     itself routes through the registry). The caller must have registered +
 *     downloaded the sherpa model before reaching here.
 *   - CLOUD — engine hint "cloud"; [Cloud.register] supplies the model
 *     string + API key + provider, marshalled into the cloud config JSON
 *     (including `provider`) and forwarded verbatim to the routed engine's
 *     create op. The provider (e.g. "sarvam") is data in the config, not a
 *     distinct engine.
 *
 * Backend dispatch keys off the structured [HybridBackendKind] proto enum
 * (via [HybridModel.backend]) — never a raw string. Mirrors Swift's
 * HybridSTTRouter.createService(for:) semantics over the JNI handle ABI.
 */

package com.runanywhere.sdk.hybrid

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode

/**
 * Bridges a typed [HybridModel] into a raw native STT service handle
 * (returned as `Long` from the JNI layer). Internal — public callers use
 * [HybridSTTRouter].
 */
internal object HybridRouterBridgeAdapter {
    /**
     * Construct a native STT service for [model] and return its handle. The
     * router then attaches the handle to its offline or online slot via
     * `racSttHybridRouterSet*Service`.
     *
     * @throws SDKException if the backend kind is unsupported or the native
     *         create fails (e.g. model id not in the registry, cloud entry
     *         not registered, plugin missing).
     */
    fun createService(model: HybridModel): Long {
        val handle =
            when (model.backend) {
                HybridBackendKind.HYBRID_BACKEND_SHERPA -> {
                    requireSherpaRegistered()
                    // The model-registry path-resolution lives in
                    // racSttServiceCreate; it routes the create through the same
                    // plugin registry (hint "sherpa") as the online side.
                    RunAnywhereBridge.racSttServiceCreate(model.id)
                }
                HybridBackendKind.HYBRID_BACKEND_CLOUD ->
                    RunAnywhereBridge.racSttHybridRouterCreateService(
                        engineHint = CLOUD_ENGINE_HINT,
                        // Cloud engine takes everything via config_json; no model path.
                        modelIdOrPath = "",
                        configJson = Cloud.configJson(model.id),
                    )
                else -> throw serviceUnavailable("Unsupported hybrid STT backend: ${model.backend}")
            }
        if (handle == 0L) {
            throw serviceUnavailable(
                "Failed to create native STT service for backend=${model.backend} model='${model.id}'",
            )
        }
        return handle
    }

    /**
     * Fail early with an actionable message when the on-device sherpa plugin
     * isn't in the native plugin registry yet. Without this guard the offline
     * service create bottoms out in an opaque `rac_plugin_route` failure
     * (handle == 0) that gives no hint about the missing prerequisite.
     *
     * The sherpa engine registers under the name "sherpa" when its native
     * library is loaded — on Android that happens via the ONNX/sherpa module
     * (`ONNX.register()` → `System.loadLibrary("rac_backend_sherpa")`), which
     * must run before `HybridSTTRouter().setPair(...)`.
     */
    private fun requireSherpaRegistered() {
        val names = RunAnywhereBridge.racRegistryGetRegisteredNames()?.toList().orEmpty()
        if (names.none { it.equals("sherpa", ignoreCase = true) }) {
            throw serviceUnavailable(
                "sherpa STT backend is not registered. Load the on-device backend first " +
                    "(ONNX.register() for sherpa, Cloud.register() for cloud) before " +
                    "HybridSTTRouter().setPair(...). " +
                    "Registered plugins: ${names.joinToString().ifEmpty { "(none)" }}",
            )
        }
    }

    /**
     * Release the native handle [handle] returned by [createService].
     * No-op when [handle] is 0. Both sides route destruction through the
     * unified registry destroy thunk (`rac_stt_destroy`), so no per-backend
     * dispatch is needed.
     */
    fun destroyService(handle: Long) {
        if (handle == 0L) {
            return
        }
        RunAnywhereBridge.racSttHybridRouterDestroyService(handle)
    }

    private fun serviceUnavailable(message: String): SDKException =
        SDKException.make(
            code = ProtoErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
            message = message,
        )

    /** Engine hint pinned as `preferred_engine_name` for the cloud route. */
    private const val CLOUD_ENGINE_HINT = "cloud"
}
