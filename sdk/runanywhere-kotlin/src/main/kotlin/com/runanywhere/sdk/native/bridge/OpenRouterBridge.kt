/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JNI bridge for the OpenRouter LLM backend factory.
 *
 * Returns an opaque `rac_llm_service_t*` handle (as Long) that callers
 * register with the hybrid router via RunAnywhereBridge.racLlmHybridRouter*.
 * The OpenRouter JNI symbols live in the rac_backend_openrouter target;
 * on Android they are packaged inside the same shared library as the
 * commons JNI.
 */

package com.runanywhere.sdk.native.bridge

/**
 * Low-level JNI entry points for constructing OpenRouter LLM services.
 *
 * Public callers should use the typed [com.runanywhere.sdk.public.hybrid.RACRouter]
 * facade and [com.runanywhere.sdk.public.hybrid.BACKEND.OPENROUTER.register]
 * — this bridge is the thin layer that maps Kotlin types onto the native
 * `rac_llm_openrouter_*` C functions exported by `engines/openrouter/`.
 */
object OpenRouterBridge {
    init {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
    }

    /**
     * Convenience factory taking the api key and model string directly.
     * Equivalent to building the JSON `{"api_key": ..., "model": ...}`
     * and calling [racLlmOpenRouterCreateFromJson].
     *
     * @param apiKey OpenRouter API key.
     * @param model  OpenRouter model string (e.g. `"openai/gpt-4o-mini"`).
     * @return Native `rac_llm_service_t*` cast to Long, or 0 on failure.
     */
    @JvmStatic external fun racLlmOpenRouterCreate(apiKey: String, model: String): Long

    /**
     * Full-knobs factory taking a serialized config JSON. Schema is
     * documented in `engines/openrouter/include/rac/backends/rac_llm_openrouter.h`
     * (keys: `api_key`, `model`, `base_url`, `timeout_ms`, `http_referer`,
     * `x_title`).
     *
     * @param configJson JSON string with required + optional config fields.
     * @return Native handle cast to Long, or 0 on failure.
     */
    @JvmStatic external fun racLlmOpenRouterCreateFromJson(configJson: String): Long

    /**
     * Destroy a handle returned by either factory. Safe to call with 0.
     * Frees the internal HTTP-client state and the wrapping
     * `rac_llm_service_t` struct.
     */
    @JvmStatic external fun racLlmOpenRouterDestroy(handle: Long)
}
