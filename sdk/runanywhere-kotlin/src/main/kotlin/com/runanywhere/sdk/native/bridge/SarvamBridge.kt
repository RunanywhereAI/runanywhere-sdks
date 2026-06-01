/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JNI bridge for the Sarvam STT backend factory.
 *
 * Returns an opaque `rac_stt_service_t*` handle (as Long) that callers
 * hand to whatever STT facade consumes the engine. The Sarvam JNI symbols
 * live in the rac_backend_sarvam target; on Android they are packaged
 * inside the same shared library as the commons JNI.
 */

package com.runanywhere.sdk.native.bridge

/**
 * Low-level JNI entry points for constructing Sarvam STT services.
 *
 * Public callers should use [com.runanywhere.sdk.public.hybrid.BACKEND.SARVAM.register]
 * — this bridge is the thin layer that maps Kotlin types onto the native
 * `rac_stt_sarvam_*` C functions exported by `engines/sarvam/`.
 */
object SarvamBridge {
    init {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
    }

    /**
     * Convenience factory taking the api key and model string directly.
     * Equivalent to building the JSON `{"api_key": ..., "model": ...}`
     * and calling [racSttSarvamCreateFromJson].
     *
     * @param apiKey Sarvam API subscription key.
     * @param model  Saarika model id (e.g. `"saarika:v2.5"`).
     * @return Native `rac_stt_service_t*` cast to Long, or 0 on failure.
     */
    @JvmStatic external fun racSttSarvamCreate(apiKey: String, model: String): Long

    /**
     * Full-knobs factory taking a serialized config JSON. Schema is
     * documented in `engines/sarvam/include/rac/backends/rac_stt_sarvam.h`
     * (keys: `api_key`, `model`, `language_code`, `base_url`, `timeout_ms`).
     *
     * @param configJson JSON string with required + optional config fields.
     * @return Native handle cast to Long, or 0 on failure.
     */
    @JvmStatic external fun racSttSarvamCreateFromJson(configJson: String): Long

    /**
     * Destroy a handle returned by either factory. Safe to call with 0.
     */
    @JvmStatic external fun racSttSarvamDestroy(handle: Long)
}