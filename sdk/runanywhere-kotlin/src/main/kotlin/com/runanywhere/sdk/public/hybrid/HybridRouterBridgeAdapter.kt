/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Builds a native service handle (a Long) for a given BackendId+RACModel
 * across LLM and STT capabilities, and tears it down again on close().
 *
 * Resolution rules:
 *   - LLAMACPP.TEXTGEN — rac_llm_create via the C model registry.
 *   - OPENROUTER.TEXTGEN — BACKEND.OPENROUTER.register(...) lookup, then
 *     OpenRouterBridge.racLlmOpenRouterCreateFromJson.
 *   - SHERPA.STT — rac_stt_create via the C model registry.
 *   - SARVAM.STT — BACKEND.SARVAM.register(...) lookup, then
 *     SarvamBridge.racSttSarvamCreateFromJson.
 */

package com.runanywhere.sdk.public.hybrid

import com.runanywhere.sdk.native.bridge.OpenRouterBridge
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.native.bridge.SarvamBridge
import org.json.JSONObject

/**
 * Bridges the typed Kotlin [BackendId] + [RACModel] inputs into raw
 * native service handles (returned as `Long` from the JNI layer).
 * Internal — public callers use [RACRouter.llm] or [RACRouter.stt].
 */
internal object HybridRouterBridgeAdapter {

    /**
     * Construct a native service for [backend] + [model] and return its
     * handle. The router then attaches the handle to its offline or
     * online slot via the matching capability-specific
     * `rac*HybridRouterSet*Service` thunk.
     *
     * Dispatch keys on `(family, capability)` since the same family can
     * potentially serve multiple capabilities later.
     *
     * @throws IllegalStateException if the native call fails (e.g. model
     *         id not in the registry, cloud entry not registered).
     */
    fun createService(backend: BackendId, model: RACModel): Long {
        val key = backend.family to backend.capability
        val handle = when (key) {
            "LLAMACPP" to "TEXTGEN" -> RunAnywhereBridge.racLlmServiceCreate(model.id)
            "OPENROUTER" to "TEXTGEN" -> createOpenRouterService(model.id)
            "SHERPA" to "STT" -> RunAnywhereBridge.racSttServiceCreate(model.id)
            "SARVAM" to "STT" -> createSarvamService(model.id)
            else -> error("Unknown backend: ${backend.family}.${backend.capability}")
        }
        check(handle != 0L) {
            "Failed to create native service for ${backend.family}.${backend.capability} model=${model.id}"
        }
        return handle
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
            "LLAMACPP" to "TEXTGEN" -> RunAnywhereBridge.racLlmServiceDestroy(handle)
            "OPENROUTER" to "TEXTGEN" -> OpenRouterBridge.racLlmOpenRouterDestroy(handle)
            "SHERPA" to "STT" -> RunAnywhereBridge.racSttServiceDestroy(handle)
            "SARVAM" to "STT" -> SarvamBridge.racSttSarvamDestroy(handle)
            else -> RunAnywhereBridge.racLlmServiceDestroy(handle)
        }
    }

    /**
     * Look up [id] in [BACKEND.OPENROUTER]'s registry, build the config
     * JSON the OpenRouter factory expects, and call into JNI.
     */
    private fun createOpenRouterService(id: String): Long {
        val entry = BACKEND.OPENROUTER.lookup(id)
            ?: error(
                "OpenRouter model id '$id' not registered. " +
                    "Call BACKEND.OPENROUTER.register(id, model, apiKey) at app startup.",
            )
        val configJson = JSONObject()
            .put("api_key", entry.apiKey)
            .put("model", entry.model)
        entry.baseUrl?.let { configJson.put("base_url", it) }
        entry.timeoutMs?.let { configJson.put("timeout_ms", it) }
        entry.httpReferer?.let { configJson.put("http_referer", it) }
        entry.xTitle?.let { configJson.put("x_title", it) }
        return OpenRouterBridge.racLlmOpenRouterCreateFromJson(configJson.toString())
    }

    /**
     * Look up [id] in [BACKEND.SARVAM]'s registry, build the config JSON
     * the Sarvam factory expects, and call into JNI.
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
