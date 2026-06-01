/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Builds a native rac_stt_service_t handle (a Long) for a given
 * BackendId + RACModel, and tears it down again on close().
 *
 * Resolution rules:
 *   - SHERPA.STT — rac_stt_create via the C model registry. The caller must
 *     have registered + downloaded the sherpa model before reaching here.
 *   - SARVAM.STT — BACKEND.SARVAM.register(...) lookup supplies the model
 *     string + API key; SarvamBridge.racSttSarvamCreateFromJson builds it.
 */

package com.runanywhere.sdk.public.hybrid

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.native.bridge.SarvamBridge
import org.json.JSONObject

/**
 * Bridges the typed Kotlin [BackendId] + [RACModel] inputs into raw
 * native STT service handles (returned as `Long` from the JNI layer).
 * Internal — public callers use [RACRouter.stt].
 */
internal object HybridRouterBridgeAdapter {

    /**
     * Construct a native STT service for [backend] + [model] and return its
     * handle. The router then attaches the handle to its offline or online
     * slot via `racSttHybridRouterSet*Service`.
     *
     * @throws IllegalStateException if the native call fails (e.g. model id
     *         not in the registry, Sarvam entry not registered).
     */
    fun createService(backend: BackendId, model: RACModel): Long {
        val key = backend.family to backend.capability
        val handle = when (key) {
            "SHERPA" to "STT" -> {
                requireSherpaRegistered()
                RunAnywhereBridge.racSttServiceCreate(model.id)
            }
            "SARVAM" to "STT" -> createSarvamService(model.id)
            else -> error("Unknown backend: ${backend.family}.${backend.capability}")
        }
        check(handle != 0L) {
            "Failed to create native service for ${backend.family}.${backend.capability} model=${model.id}"
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
     * must run before `RACRouter.stt.init(...)`.
     */
    private fun requireSherpaRegistered() {
        val names = RunAnywhereBridge.racRegistryGetRegisteredNames()?.toList().orEmpty()
        check(names.any { it.equals("sherpa", ignoreCase = true) }) {
            "sherpa STT backend is not registered. Load the on-device backend first " +
                "(e.g. ONNX.register() on Android) before RACRouter.stt.init(...). " +
                "Registered plugins: ${names.joinToString().ifEmpty { "(none)" }}"
        }
    }

    /**
     * Release the native handle [handle] returned by [createService].
     * No-op when [handle] is 0. Routes destruction to the right native
     * destroy fn based on [backend].
     */
    fun destroyService(backend: BackendId?, handle: Long) {
        if (handle == 0L) {
            return
        }
        val key = backend?.let { it.family to it.capability }
        when (key) {
            "SARVAM" to "STT" -> SarvamBridge.racSttSarvamDestroy(handle)
            else -> RunAnywhereBridge.racSttServiceDestroy(handle)
        }
    }

    /**
     * Look up [id] in [BACKEND.SARVAM]'s registry, build the config JSON the
     * Sarvam factory expects, and call into JNI.
     */
    private fun createSarvamService(id: String): Long {
        val entry = BACKEND.SARVAM.lookup(id)
            ?: error(
                "Sarvam model id '$id' not registered. " +
                    "Call BACKEND.SARVAM.register(id, model, apiKey) at app startup.",
            )
        val configJson = JSONObject()
            .put("api_key", entry.apiKey)
            .put("model", entry.model)
        entry.languageCode?.let { configJson.put("language_code", it) }
        entry.baseUrl?.let { configJson.put("base_url", it) }
        entry.timeoutMs?.let { configJson.put("timeout_ms", it) }
        return SarvamBridge.racSttSarvamCreateFromJson(configJson.toString())
    }
}
