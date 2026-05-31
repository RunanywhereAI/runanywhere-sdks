/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public backend identifiers used by RACRouter.<capability>.init(...).
 * Mirrors HybridBackendKind in idl/hybrid_router.proto.
 *
 * Cloud backends (OpenRouter) also expose a register/lookup table so the
 * caller can pre-register model entries at app startup and refer to them
 * by registry id from the router — matching the offline-model registry
 * pattern (rac_register_model in core commons).
 */

package com.runanywhere.sdk.public.hybrid

import java.util.concurrent.ConcurrentHashMap

/**
 * Catalog of supported backend families.
 *
 * Each nested object is a backend family (LLAMACPP, OPENROUTER, ...) that
 * exposes one [BackendId] per capability (TEXTGEN, embedding, ...). The
 * router pairs two [BackendId] values — one on-device and one cloud — at
 * `RACRouter.llm.init(...)` time:
 *
 *     RACRouter.llm.init(
 *         backendOffline = BACKEND.LLAMACPP.TEXTGEN,
 *         backendOnline  = BACKEND.OPENROUTER.TEXTGEN,
 *     )
 *
 * Cloud backends additionally expose a registration table for credentials
 * + model strings — see [OPENROUTER.register].
 */
object BACKEND {
    /** llama.cpp family (on-device). */
    object LLAMACPP {
        /** Text-generation capability. */
        val TEXTGEN: BackendId = BackendId(kind = 1, family = "LLAMACPP", capability = "TEXTGEN")
    }

    /**
     * OpenRouter family (cloud). Also acts as the in-process credential
     * + model registry — see [register].
     */
    object OPENROUTER {
        /** Text-generation capability over OpenRouter. */
        val TEXTGEN: BackendId = BackendId(kind = 2, family = "OPENROUTER", capability = "TEXTGEN")

        private val registry = ConcurrentHashMap<String, OpenRouterModelEntry>()

        /**
         * Register an OpenRouter model under [id]. Once registered, the
         * router can refer to it by [id] alone:
         *
         *     BACKEND.OPENROUTER.register(
         *         id = "claude-haiku",
         *         model = "anthropic/claude-haiku-4",
         *         apiKey = "sk-or-...",
         *     )
         *     ...
         *     router.llm.addPair(
         *         model2 = RACModel(id = "claude-haiku", modelType = ROUTER.ONLINE),
         *         ...
         *     )
         *
         * The registry is in-memory and thread-safe ([ConcurrentHashMap]).
         * Registrations live for the process lifetime unless explicitly
         * removed via [unregister] or [clear].
         *
         * @param id          App-chosen registry id (the value the router sees).
         * @param model       OpenRouter model string (e.g. "openai/gpt-4o-mini").
         * @param apiKey      OpenRouter API key.
         * @param baseUrl     Optional base URL override.
         * @param timeoutMs   Optional request timeout in milliseconds.
         * @param httpReferer Optional HTTP-Referer header for attribution.
         * @param xTitle      Optional X-Title header for attribution.
         * @throws IllegalArgumentException if any required field is blank.
         */
        @JvmStatic
        @JvmOverloads
        fun register(
            id: String,
            model: String,
            apiKey: String,
            baseUrl: String? = null,
            timeoutMs: Int? = null,
            httpReferer: String? = null,
            xTitle: String? = null,
        ) {
            require(id.isNotBlank()) { "OpenRouter registry id must be non-blank" }
            require(model.isNotBlank()) { "OpenRouter model string must be non-blank" }
            require(apiKey.isNotBlank()) { "OpenRouter apiKey must be non-blank" }
            registry[id] = OpenRouterModelEntry(
                id = id,
                model = model,
                apiKey = apiKey,
                baseUrl = baseUrl,
                timeoutMs = timeoutMs,
                httpReferer = httpReferer,
                xTitle = xTitle,
            )
        }

        /**
         * Remove a previously registered entry.
         *
         * @return `true` if [id] was registered (and is now gone), `false`
         *         otherwise.
         */
        @JvmStatic
        fun unregister(id: String): Boolean = registry.remove(id) != null

        /**
         * Resolve a registered entry. Returns `null` if [id] was never
         * registered. The router uses this internally before creating the
         * native OpenRouter service.
         */
        @JvmStatic
        fun lookup(id: String): OpenRouterModelEntry? = registry[id]

        /** Whether [id] is currently registered. */
        @JvmStatic
        fun isRegistered(id: String): Boolean = registry.containsKey(id)

        /** Remove every registered entry. Useful in tests. */
        @JvmStatic
        fun clear() {
            registry.clear()
        }
    }

    /**
     * Sherpa family (on-device STT). No credentials registry needed —
     * sherpa resolves its model via the standard model registry by id
     * (sherpa-onnx-whisper-tiny.en, etc.).
     */
    object SHERPA {
        /** Speech-to-text capability over sherpa-onnx. */
        val STT: BackendId = BackendId(kind = 3, family = "SHERPA", capability = "STT")
    }

    /**
     * Sarvam family (cloud). Also acts as the in-process credential
     * + model registry — see [register].
     */
    object SARVAM {
        /** Speech-to-text capability over Sarvam. */
        val STT: BackendId = BackendId(kind = 4, family = "SARVAM", capability = "STT")

        private val registry = ConcurrentHashMap<String, SarvamModelEntry>()

        /**
         * Register a Sarvam model under [id]. Once registered, callers can
         * refer to it by [id] alone:
         *
         *     BACKEND.SARVAM.register(
         *         id = "saarika",
         *         model = "saarika:v2.5",
         *         apiKey = "...",
         *         languageCode = "en-IN",
         *     )
         *
         * The registry is in-memory and thread-safe ([ConcurrentHashMap]).
         * Registrations live for the process lifetime unless explicitly
         * removed via [unregister] or [clear].
         *
         * @param id           App-chosen registry id.
         * @param model        Saarika model id (e.g. "saarika:v2.5").
         * @param apiKey       Sarvam API subscription key.
         * @param languageCode Optional BCP-47 language hint ("en-IN", "hi-IN", …).
         *                     Pass `null` (or omit) to let Sarvam auto-detect; the
         *                     engine then omits the `language_code` form field
         *                     entirely. Required-looking model variants like
         *                     `saaras:v3` reject the literal string "unknown".
         * @param baseUrl      Optional base URL override.
         * @param timeoutMs    Optional request timeout in milliseconds.
         * @throws IllegalArgumentException if any required field is blank.
         */
        @JvmStatic
        @JvmOverloads
        fun register(
            id: String,
            model: String,
            apiKey: String,
            languageCode: String? = null,
            baseUrl: String? = null,
            timeoutMs: Int? = null,
        ) {
            require(id.isNotBlank()) { "Sarvam registry id must be non-blank" }
            require(model.isNotBlank()) { "Sarvam model string must be non-blank" }
            require(apiKey.isNotBlank()) { "Sarvam apiKey must be non-blank" }
            registry[id] = SarvamModelEntry(
                id = id,
                model = model,
                apiKey = apiKey,
                languageCode = languageCode,
                baseUrl = baseUrl,
                timeoutMs = timeoutMs,
            )
        }

        @JvmStatic
        fun unregister(id: String): Boolean = registry.remove(id) != null

        @JvmStatic
        fun lookup(id: String): SarvamModelEntry? = registry[id]

        @JvmStatic
        fun isRegistered(id: String): Boolean = registry.containsKey(id)

        @JvmStatic
        fun clear() {
            registry.clear()
        }
    }
}

/**
 * Tagged backend handle. Created internally by the [BACKEND] catalog —
 * callers receive these values and pass them to the router without ever
 * constructing them directly.
 *
 * @property kind        Wire value matching `HybridBackendKind` in the
 *                       hybrid_router.proto schema.
 * @property family      Backend family name ("LLAMACPP", "OPENROUTER", ...).
 *                       The Kotlin adapter dispatches on this string.
 * @property capability  Capability name ("TEXTGEN", "EMBEDDING", ...).
 */
class BackendId internal constructor(
    val kind: Int,
    val family: String,
    val capability: String,
)

/**
 * Frozen view of an OpenRouter model registered via
 * [BACKEND.OPENROUTER.register]. Returned by [BACKEND.OPENROUTER.lookup].
 *
 * @property id          App-supplied registry id.
 * @property model       OpenRouter model string used on the wire.
 * @property apiKey      OpenRouter API key. Sensitive; never log.
 * @property baseUrl     Override of the OpenRouter endpoint, if set.
 * @property timeoutMs   Request timeout override (milliseconds), if set.
 * @property httpReferer HTTP-Referer header value, if set.
 * @property xTitle      X-Title header value, if set.
 */
data class OpenRouterModelEntry(
    val id: String,
    val model: String,
    val apiKey: String,
    val baseUrl: String? = null,
    val timeoutMs: Int? = null,
    val httpReferer: String? = null,
    val xTitle: String? = null,
)

/**
 * Frozen view of a Sarvam model registered via [BACKEND.SARVAM.register].
 * Returned by [BACKEND.SARVAM.lookup].
 *
 * @property id           App-supplied registry id.
 * @property model        Saarika model id used on the wire.
 * @property apiKey       Sarvam API subscription key. Sensitive; never log.
 * @property languageCode BCP-47 language hint, if set. `null` means omit the
 *                        field entirely so Sarvam auto-detects.
 * @property baseUrl      Override of the Sarvam endpoint, if set.
 * @property timeoutMs    Request timeout override (milliseconds), if set.
 */
data class SarvamModelEntry(
    val id: String,
    val model: String,
    val apiKey: String,
    val languageCode: String? = null,
    val baseUrl: String? = null,
    val timeoutMs: Int? = null,
)
