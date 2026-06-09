/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Developer-defined cloud STT provider callback for the hybrid router.
 *
 * The `cloud` engine ships static adapters for built-in providers (e.g.
 * "sarvam"). For any other vendor, register a [CloudSttProvider] by name via
 * [BACKEND.CLOUD.registerProvider] and tie a model to it with
 * [BACKEND.CLOUD.register] (same `provider` string). The cloud engine then
 * delegates the ENTIRE request — build, HTTP, and response parse — to the
 * callback, so a developer supports any cloud STT API (key, URL, request and
 * response shape) without a native adapter or a recompile.
 *
 * The callback runs on the engine's request thread (off the main thread); it
 * may block on network. It must be thread-safe — the engine may invoke it
 * concurrently for distinct utterances.
 */

package com.runanywhere.sdk.public.hybrid

import org.json.JSONObject

/**
 * Audio container of the bytes handed to a [CloudSttProvider]. Wire values
 * mirror the native `rac_audio_format_enum_t`.
 */
enum class CloudAudioFormat(
    val nativeValue: Int,
) {
    PCM(0),
    WAV(1),
    MP3(2),
    OPUS(3),
    AAC(4),
    FLAC(5),
    UNKNOWN(-1),
    ;

    companion object {
        fun fromNative(value: Int): CloudAudioFormat =
            entries.firstOrNull { it.nativeValue == value } ?: UNKNOWN
    }
}

/**
 * One cloud transcribe request handed to a [CloudSttProvider].
 *
 * @property provider     The provider name this entry was registered under.
 * @property model        The provider model id from [BACKEND.CLOUD.register].
 * @property apiKey        The API key from registration. Sensitive; never log.
 * @property baseUrl      Optional base-URL override from registration, if set.
 * @property languageCode Optional BCP-47 language hint, if set.
 * @property audio        Audio bytes for this utterance.
 * @property audioFormat  Container/encoding of [audio].
 * @property configJson   The full registered config as JSON, for any extra keys
 *                        a provider needs beyond the typed fields above.
 */
class CloudSttRequest(
    val provider: String,
    val model: String,
    val apiKey: String,
    val baseUrl: String?,
    val languageCode: String?,
    val audio: ByteArray,
    val audioFormat: CloudAudioFormat,
    val configJson: String,
)

/**
 * Result of a cloud transcribe.
 *
 * @property text         The transcript (empty if the provider found no speech).
 * @property languageCode Detected/echoed BCP-47 language, if the provider reports one.
 * @property confidence   Optional 0..1 confidence; leave [Float.NaN] (the default)
 *                        when the provider returns no score. The hybrid router
 *                        treats NaN as "no signal" and never cascades on it.
 */
class CloudSttResult(
    val text: String,
    val languageCode: String? = null,
    val confidence: Float = Float.NaN,
)

/**
 * Performs a complete cloud STT request host-side for one utterance.
 *
 * Implementations build and send the HTTP request (e.g. with OkHttp) and parse
 * the response into a [CloudSttResult]. Throwing is allowed — it surfaces to the
 * router as a transcribe failure (so the cascade policy can fall back).
 */
fun interface CloudSttProvider {
    fun transcribe(request: CloudSttRequest): CloudSttResult
}

/**
 * Internal JNI bridge. The native cloud engine resolves this type by the exact
 * signature `invoke(Ljava/lang/String;[BI)Ljava/lang/String;` (see
 * `rac_cloud_stt_provider_jni.cpp`), so the class/method name and shape must not
 * drift. Not part of the public API surface.
 *
 * @suppress
 */
class NativeCloudSttProvider(
    private val delegate: CloudSttProvider,
) {
    /**
     * Invoked from native. Decodes [configJson] into a [CloudSttRequest], runs
     * the delegate, and returns a result-JSON string the engine parses. Never
     * throws across the JNI boundary — failures are encoded as
     * `{"error_code": 1, "error_message": "…"}`.
     */
    fun invoke(configJson: String, audio: ByteArray, audioFormat: Int): String {
        return try {
            val config = JSONObject(configJson)
            val request =
                CloudSttRequest(
                    provider = config.optString("provider"),
                    model = config.optString("model"),
                    apiKey = config.optString("api_key"),
                    baseUrl = config.optString("base_url").ifBlank { null },
                    languageCode = config.optString("language_code").ifBlank { null },
                    audio = audio,
                    audioFormat = CloudAudioFormat.fromNative(audioFormat),
                    configJson = configJson,
                )
            val result = delegate.transcribe(request)
            JSONObject()
                .apply {
                    put("text", result.text)
                    result.languageCode?.let { put("language_code", it) }
                    if (!result.confidence.isNaN()) put("confidence", result.confidence.toDouble())
                    put("error_code", 0)
                }.toString()
        } catch (e: Throwable) {
            JSONObject()
                .put("error_code", 1)
                .put("error_message", e.message ?: "cloud STT provider failed")
                .toString()
        }
    }
}
