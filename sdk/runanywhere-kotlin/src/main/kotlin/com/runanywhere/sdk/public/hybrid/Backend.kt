/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public backend identifiers used by RACRouter.<capability>.init(...).
 * Mirrors HybridBackendKind in idl/hybrid_router.proto.
 *
 * Cloud backends (the generic "cloud" engine) also expose a
 * register/lookup table so the caller can pre-register model entries at app
 * startup and refer to them by registry id from the router — matching the
 * offline-model registry pattern (rac_register_model in core commons). The
 * concrete HTTP provider (e.g. "sarvam") is data carried in each registered
 * entry, not a distinct backend kind.
 */

package com.runanywhere.sdk.public.hybrid

import ai.runanywhere.proto.v1.HybridBackendKind
import com.runanywhere.sdk.native.bridge.CloudBridge
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.util.concurrent.ConcurrentHashMap

/**
 * Catalog of supported backend families.
 *
 * Each nested object is a backend family (SHERPA, CLOUD, ...) that exposes
 * one [BackendId] per capability. The STT router pairs two [BackendId]
 * values — one on-device and one cloud — at `RACRouter.stt.init(...)` time:
 *
 *     RACRouter.stt.init(
 *         backendOffline = BACKEND.SHERPA.STT,
 *         backendOnline  = BACKEND.CLOUD.STT,
 *     )
 *
 * Cloud backends additionally expose a registration table for credentials
 * + model strings + provider — see [CLOUD.register].
 */
object BACKEND {
    /** Default cloud provider when a registration omits `provider`. */
    internal const val DEFAULT_PROVIDER = "sarvam"

    /**
     * Sherpa family (on-device STT). No credentials registry needed —
     * sherpa resolves its model via the standard model registry by id
     * (sherpa-onnx-whisper-tiny.en, etc.).
     */
    object SHERPA {
        /** Speech-to-text capability over sherpa-onnx. */
        val STT: BackendId =
            BackendId(kind = HybridBackendKind.HYBRID_BACKEND_SHERPA, family = "SHERPA", capability = "STT")
    }

    /**
     * Cloud family (cloud STT over the generic "cloud" engine). Also acts
     * as the in-process credential + model + provider registry — see
     * [register]. The concrete HTTP provider (default "sarvam") is selected
     * per registered entry and forwarded to the engine via
     * `config_json["provider"]`; there is no provider-specific Kotlin type.
     */
    object CLOUD {
        /**
         * Speech-to-text capability over the cloud engine. Carries the
         * default provider ("sarvam") in the [BackendId]; per-model providers
         * come from the [register] entry looked up at service-create time.
         */
        val STT: BackendId =
            BackendId(
                kind = HybridBackendKind.HYBRID_BACKEND_CLOUD,
                family = "CLOUD",
                capability = "STT",
                provider = DEFAULT_PROVIDER,
            )

        private val registry = ConcurrentHashMap<String, CloudModelEntry>()

        /**
         * Fire the native "cloud" plugin registration exactly once for the
         * process. Mirrors `ONNX.register()` / `LlamaCPP.register()` — the
         * engine must be in the unified plugin registry before the hybrid
         * router can route the online side via
         * `racSttHybridRouterCreateService("cloud", …)`. Tolerant of the
         * native already-registered code so repeated registrations are safe.
         */
        private fun ensurePluginRegistered() {
            if (pluginRegistered) {
                return
            }
            synchronized(pluginRegisterLock) {
                if (pluginRegistered) {
                    return
                }
                val rc = CloudBridge.nativeRegister()
                // RAC_SUCCESS or "module already registered" both mean the
                // plugin is now routable; any other code leaves the flag unset
                // so a later register() retries.
                if (rc == RunAnywhereBridge.RAC_SUCCESS ||
                    rc == RunAnywhereBridge.RAC_ERROR_MODULE_ALREADY_REGISTERED
                ) {
                    pluginRegistered = true
                }
            }
        }

        @Volatile
        private var pluginRegistered = false
        private val pluginRegisterLock = Any()

        /**
         * Register a cloud STT model under [id]. Once registered, callers can
         * refer to it by [id] alone:
         *
         *     BACKEND.CLOUD.register(
         *         id = "saarika",
         *         model = "saarika:v2.5",
         *         apiKey = "...",
         *         provider = "sarvam",
         *         languageCode = "en-IN",
         *     )
         *
         * The registry is in-memory and thread-safe ([ConcurrentHashMap]).
         * Registrations live for the process lifetime unless explicitly
         * removed via [unregister] or [clear].
         *
         * @param id           App-chosen registry id.
         * @param model        Provider model id (e.g. "saarika:v2.5").
         * @param apiKey       Provider API subscription key.
         * @param provider     Cloud provider selected for this entry. Defaults
         *                     to "sarvam". Forwarded to the cloud engine via
         *                     `config_json["provider"]`.
         * @param languageCode Optional BCP-47 language hint ("en-IN", "hi-IN", …).
         *                     Pass `null` (or omit) to let the provider auto-detect;
         *                     the engine then omits the `language_code` form field
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
            provider: String = DEFAULT_PROVIDER,
            languageCode: String? = null,
            baseUrl: String? = null,
            timeoutMs: Int? = null,
        ) {
            require(id.isNotBlank()) { "Cloud registry id must be non-blank" }
            require(model.isNotBlank()) { "Cloud model string must be non-blank" }
            require(apiKey.isNotBlank()) { "Cloud apiKey must be non-blank" }
            require(provider.isNotBlank()) { "Cloud provider must be non-blank" }
            // Put the "cloud" engine in the native plugin registry at the
            // same bootstrap point the app registers credentials — symmetric to
            // ONNX.register() seeding the on-device backend.
            ensurePluginRegistered()
            registry[id] =
                CloudModelEntry(
                    id = id,
                    model = model,
                    apiKey = apiKey,
                    provider = provider,
                    languageCode = languageCode,
                    baseUrl = baseUrl,
                    timeoutMs = timeoutMs,
                )
        }

        @JvmStatic
        fun unregister(id: String): Boolean = registry.remove(id) != null

        @JvmStatic
        fun lookup(id: String): CloudModelEntry? = registry[id]

        @JvmStatic
        fun isRegistered(id: String): Boolean = registry.containsKey(id)

        @JvmStatic
        fun clear() {
            registry.clear()
        }

        // Developer-defined providers, kept by name so re-registration and
        // [unregisterProvider] are well-defined. The native side holds the
        // authoritative GlobalRef; this map mirrors it for lifecycle clarity.
        private val providerHandlers = ConcurrentHashMap<String, NativeCloudSttProvider>()

        /**
         * Register (or replace) a developer-defined cloud STT [provider]. The
         * [handler] performs the whole request host-side (build + HTTP + parse),
         * so any vendor works without a native adapter. Tie a model to it by
         * calling [register] with the same `provider` string:
         *
         *     BACKEND.CLOUD.registerProvider("deepgram") { req ->
         *         // build + POST with OkHttp, parse the JSON …
         *         CloudSttResult(text = transcript, confidence = score)
         *     }
         *     BACKEND.CLOUD.register(
         *         id = "dg-nova2", model = "nova-2", apiKey = "…",
         *         provider = "deepgram", baseUrl = "https://api.deepgram.com",
         *     )
         *
         * The handler is invoked on the router's request thread and may block on
         * network. Built-in providers (e.g. "sarvam") cannot be shadowed — a
         * static adapter always wins over a host callback of the same name.
         *
         * @throws IllegalArgumentException if [provider] is blank.
         * @throws IllegalStateException if native registration fails.
         */
        @JvmStatic
        fun registerProvider(provider: String, handler: CloudSttProvider) {
            require(provider.isNotBlank()) { "Cloud provider name must be non-blank" }
            ensurePluginRegistered()
            val native = NativeCloudSttProvider(handler)
            val rc = RunAnywhereBridge.racCloudRegisterSttProvider(provider, native)
            check(rc == RunAnywhereBridge.RAC_SUCCESS) {
                "Failed to register cloud provider '$provider' (rc=$rc)"
            }
            providerHandlers[provider] = native
        }

        /**
         * Remove a developer-defined provider previously registered via
         * [registerProvider]. Idempotent for unknown names.
         */
        @JvmStatic
        fun unregisterProvider(provider: String) {
            if (provider.isBlank()) {
                return
            }
            RunAnywhereBridge.racCloudUnregisterSttProvider(provider)
            providerHandlers.remove(provider)
        }
    }

    /**
     * Backwards-compatible alias for the Sarvam provider over the generic
     * [CLOUD] backend. Delegates every call to [CLOUD] with
     * `provider = "sarvam"`, so existing `BACKEND.SARVAM.*` callers keep
     * working while the engine is the single generic cloud plugin. Prefer
     * `BACKEND.CLOUD` for new code.
     */
    object SARVAM {
        /** Speech-to-text capability over the cloud engine (provider sarvam). */
        @JvmField
        val STT: BackendId = CLOUD.STT

        /**
         * Register a Sarvam model. Identical to [CLOUD.register] with
         * `provider = "sarvam"` pinned.
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
        ) = CLOUD.register(
            id = id,
            model = model,
            apiKey = apiKey,
            provider = DEFAULT_PROVIDER,
            languageCode = languageCode,
            baseUrl = baseUrl,
            timeoutMs = timeoutMs,
        )

        @JvmStatic
        fun unregister(id: String): Boolean = CLOUD.unregister(id)

        @JvmStatic
        fun lookup(id: String): CloudModelEntry? = CLOUD.lookup(id)

        @JvmStatic
        fun isRegistered(id: String): Boolean = CLOUD.isRegistered(id)

        @JvmStatic
        fun clear() = CLOUD.clear()
    }
}

/**
 * Tagged backend handle. Created internally by the [BACKEND] catalog —
 * callers receive these values and pass them to the router without ever
 * constructing them directly.
 *
 * @property kind        Structured backend identity (generated
 *                       `HybridBackendKind` from the hybrid_router.proto
 *                       schema). The adapter dispatches on this proto enum
 *                       (not the [family] string) when routing service
 *                       creation through the unified plugin registry.
 * @property family      Backend family name ("SHERPA", "CLOUD", ...).
 * @property capability  Capability name ("STT", ...).
 * @property provider    Concrete cloud provider for a
 *                       [HybridBackendKind.HYBRID_BACKEND_CLOUD] backend
 *                       (e.g. "sarvam"); written into the proto descriptor's
 *                       `provider` field. Empty for non-cloud backends.
 */
class BackendId internal constructor(
    val kind: HybridBackendKind,
    val family: String,
    val capability: String,
    val provider: String = "",
) {
    /** Alias for [kind]; the adapter dispatches on this proto enum. */
    internal val kindEnum: HybridBackendKind
        get() = kind
}

/**
 * Frozen view of a cloud STT model registered via [BACKEND.CLOUD.register].
 * Returned by [BACKEND.CLOUD.lookup].
 *
 * @property id           App-supplied registry id.
 * @property model        Provider model id used on the wire.
 * @property apiKey       Provider API subscription key. Sensitive; never log.
 * @property provider     Cloud provider for this entry (e.g. "sarvam");
 *                        forwarded to the engine via `config_json["provider"]`.
 * @property languageCode BCP-47 language hint, if set. `null` means omit the
 *                        field entirely so the provider auto-detects.
 * @property baseUrl      Override of the provider endpoint, if set.
 * @property timeoutMs    Request timeout override (milliseconds), if set.
 */
data class CloudModelEntry(
    val id: String,
    val model: String,
    val apiKey: String,
    val provider: String = BACKEND.DEFAULT_PROVIDER,
    val languageCode: String? = null,
    val baseUrl: String? = null,
    val timeoutMs: Int? = null,
)
