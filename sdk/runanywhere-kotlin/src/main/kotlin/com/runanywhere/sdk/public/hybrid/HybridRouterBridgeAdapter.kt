/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Builds a native rac_stt_service_t handle (a Long) for a given
 * BackendId + RACModel, and tears it down again on close().
 *
 * BOTH sides are created through the SAME unified registry-routed factory
 * (`racSttHybridRouterCreateService`), which resolves the engine via
 * `rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, hint=<engine>)` →
 * `stt_ops->create`. There is no bespoke per-engine factory on the router
 * path:
 *   - SHERPA — engine hint "sherpa", on-device model path resolved through
 *     the C model registry ([RunAnywhereBridge.racSttServiceCreate], which
 *     itself routes through the registry). The caller must have registered +
 *     downloaded the sherpa model before reaching here.
 *   - CLOUD — engine hint "cloud"; [BACKEND.CLOUD.register] supplies the
 *     model string + API key + provider, marshalled into the cloud config JSON
 *     (including `provider`) and forwarded verbatim to the routed engine's
 *     create op. The provider (e.g. "sarvam") is data in the config, not a
 *     distinct engine.
 *
 * Backend / capability dispatch keys off the structured [HybridBackendKind]
 * proto enum (via [BackendId.kind]) — never a raw string.
 */

package com.runanywhere.sdk.public.hybrid

import ai.runanywhere.proto.v1.CloudSttBackendConfig
import ai.runanywhere.proto.v1.HybridBackendKind
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
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
     *         not in the registry, cloud entry not registered).
     */
    fun createService(backend: BackendId, model: RACModel): Long {
        val handle =
            when (backend.kindEnum) {
                HybridBackendKind.HYBRID_BACKEND_SHERPA -> {
                    requireSherpaRegistered()
                    // The model-registry path-resolution lives in
                    // racSttServiceCreate; it routes the create through the same
                    // plugin registry (hint "sherpa") as the online side.
                    RunAnywhereBridge.racSttServiceCreate(model.id)
                }
                HybridBackendKind.HYBRID_BACKEND_CLOUD -> createCloudService(model.id, backend.provider)
                else -> error("Unsupported hybrid backend: ${backend.family}.${backend.capability}")
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

    /**
     * Look up [id] in [BACKEND.CLOUD]'s registry, build the config JSON the
     * cloud engine expects, and create the service through the
     * registry-routed factory with engine hint "cloud".
     *
     * The concrete provider is carried in `config_json["provider"]` — taken
     * from the registered entry, falling back to the backend's [backendProvider]
     * (default "sarvam"). Commons injects a default too, but we pass it
     * explicitly so the routed engine never has to guess.
     */
    private fun createCloudService(id: String, backendProvider: String): Long {
        val entry =
            BACKEND.CLOUD.lookup(id)
                ?: error(
                    "Cloud model id '$id' not registered. " +
                        "Call BACKEND.CLOUD.register(id, model, apiKey) at app startup.",
                )
        val provider = entry.provider.ifBlank { backendProvider }.ifBlank { BACKEND.DEFAULT_PROVIDER }
        // Carry the cloud config in the generated wire-schema shape. The
        // optional fields stay at their proto defaults (empty/0) when the entry
        // omits them; toSnakeCaseJson() then drops those so the provider
        // auto-detects (language) / uses its own default (base URL / timeout)
        // rather than seeing a literal empty value.
        val config =
            CloudSttBackendConfig(
                provider = provider,
                model = entry.model,
                api_key = entry.apiKey,
                language_code = entry.languageCode.orEmpty(),
                base_url = entry.baseUrl.orEmpty(),
                timeout_ms = entry.timeoutMs ?: 0,
            )
        return RunAnywhereBridge.racSttHybridRouterCreateService(
            engineHint = CLOUD_ENGINE_HINT,
            // Cloud engine takes everything via config_json; no model path.
            modelIdOrPath = "",
            configJson = config.toSnakeCaseJson(),
        )
    }

    /**
     * Serialise a [CloudSttBackendConfig] to the snake_case JSON the cloud_stt
     * engine reads. The generated Wire JSON encoder emits camelCase
     * (`apiKey`, `languageCode`, …) per the proto `jsonName`, which the engine
     * does NOT understand — so build the snake_case object explicitly here.
     * Optional fields at their proto default are omitted so the provider
     * auto-detects / falls back to its own defaults.
     */
    private fun CloudSttBackendConfig.toSnakeCaseJson(): String {
        val json =
            JSONObject()
                .put("provider", provider)
                .put("api_key", api_key)
                .put("model", model)
        if (language_code.isNotEmpty()) json.put("language_code", language_code)
        if (base_url.isNotEmpty()) json.put("base_url", base_url)
        if (timeout_ms != 0) json.put("timeout_ms", timeout_ms)
        return json.toString()
    }

    /** Engine hint pinned as `preferred_engine_name` for the cloud route. */
    private const val CLOUD_ENGINE_HINT = "cloud"
}
