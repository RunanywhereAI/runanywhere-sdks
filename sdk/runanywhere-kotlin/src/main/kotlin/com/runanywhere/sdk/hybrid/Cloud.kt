/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Generic cloud backend registration + credential/model registry.
 *
 * `Cloud.register()` folds the cloud engine plugin into the commons plugin
 * registry by calling `rac_backend_cloud_register()` (via CloudBridge) — the
 * exact mirror of `ONNX.register()` / `LlamaCPP.register()`. Once registered,
 * the unified "cloud" plugin serves RAC_PRIMITIVE_TRANSCRIBE and is routable
 * via `rac_plugin_route(RAC_PRIMITIVE_TRANSCRIBE, …, hint="cloud")`, which is
 * how the hybrid router creates the online STT service. The concrete HTTP
 * provider (Sarvam first) is selected per model via the create config's
 * `"provider"` field, not by a distinct plugin.
 *
 * The credential/model registry mirrors Swift's Cloud.swift: the app
 * pre-registers a provider + model string + API key under an id at startup,
 * and the router refers to it by id (the id is the HybridModel.id for the
 * online side). Registration is process-lifetime + thread-safe.
 */

package com.runanywhere.sdk.hybrid

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.CloudBridge
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A registered cloud-STT model: the provider, the wire model string + the
 * credentials the engine needs, keyed by an app-chosen id. Backed by the
 * generated `CloudSttBackendConfig` (provider / model / api_key /
 * language_code / base_url / timeout_ms). Unset optionals map to the proto's
 * empty-string / zero defaults. Mirrors Swift's `Cloud.ModelEntry`.
 */
typealias CloudModelEntry = ai.runanywhere.proto.v1.CloudSttBackendConfig

/**
 * Generic cloud speech-to-text backend. Fronts one or more HTTP STT providers
 * (Sarvam first); the provider is data carried in each registered model entry.
 * Mirrors Swift's `Cloud` enum.
 */
object Cloud {
    private val logger = SDKLogger("Cloud")

    /** Default cloud STT provider when a caller omits one. */
    const val DEFAULT_PROVIDER = "sarvam"

    // Plugin registration

    /** Guards the one-time plugin registration (mirrors Swift's registrationState). */
    private val registrationState = AtomicBoolean(false)

    /**
     * Register the cloud backend with the commons plugin registry.
     *
     * Calls `rac_backend_cloud_register()` so the unified "cloud" plugin
     * (RAC_PRIMITIVE_TRANSCRIBE) becomes routable. Safe to call multiple
     * times — subsequent calls are no-ops, and the C side treats
     * `RAC_ERROR_MODULE_ALREADY_REGISTERED` as success. The result is logged
     * rather than thrown so a host without the engine still boots.
     */
    @JvmStatic
    fun register() {
        if (!registrationState.compareAndSet(false, true)) {
            logger.debug("Cloud already registered, returning")
            return
        }

        logger.info("Registering cloud backend with commons registry...")
        val rc = CloudBridge.nativeRegister()
        if (rc != RunAnywhereBridge.RAC_SUCCESS && rc != RunAnywhereBridge.RAC_ERROR_MODULE_ALREADY_REGISTERED) {
            // Roll back the flag so a later retry (e.g. after the engine is
            // linked in) can re-attempt registration.
            registrationState.set(false)
            logger.error("Cloud registration failed: rc=$rc")
            return
        }

        logger.info("cloud backend registered (cloud STT, default provider $DEFAULT_PROVIDER)")
    }

    /** Unregister the cloud backend from the commons registry. */
    @JvmStatic
    fun unregister() {
        if (!registrationState.getAndSet(false)) {
            return
        }
        CloudBridge.nativeUnregister()
        logger.info("cloud backend unregistered")
    }

    // Credential / model registry

    /** id → entry. In-memory, process-lifetime, thread-safe. */
    private val registry = ConcurrentHashMap<String, CloudModelEntry>()

    /**
     * Register a cloud-STT model under [id] so the router can refer to it by
     * id from [HybridModel.onlineCloud]:
     *
     *     Cloud.register(
     *         id = "saaras",
     *         model = "saaras:v3",
     *         apiKey = "...",
     *         provider = "sarvam",   // default; selects the cloud HTTP provider
     *         languageCode = null,   // null = let the provider auto-detect
     *     )
     *
     * @param id           App-chosen registry id (becomes the online HybridModel.id).
     * @param provider     Concrete cloud STT provider ("sarvam" by default).
     *                     Carried into the config JSON as `"provider"` so the
     *                     cloud engine selects the right HTTP backend.
     * @param model        Provider model id (e.g. "saaras:v3" for Sarvam).
     * @param apiKey       Provider API subscription key. Sensitive; never logged.
     * @param languageCode Optional BCP-47 hint ("en-IN", …). `null` = auto-detect
     *                     (the engine omits the language_code field).
     * @param baseUrl      Optional endpoint override.
     * @param timeoutMs    Optional request timeout (milliseconds).
     * @throws IllegalArgumentException if any required field is blank.
     */
    @JvmStatic
    @JvmOverloads
    fun register(
        id: String,
        provider: String = DEFAULT_PROVIDER,
        model: String,
        apiKey: String,
        languageCode: String? = null,
        baseUrl: String? = null,
        timeoutMs: Int? = null,
    ) {
        require(id.isNotBlank()) { "Cloud registry id must be non-blank" }
        require(provider.isNotBlank()) { "Cloud provider must be non-blank" }
        require(model.isNotBlank()) { "Cloud model string must be non-blank" }
        require(apiKey.isNotBlank()) { "Cloud apiKey must be non-blank" }
        registry[id] =
            CloudModelEntry(
                provider = provider,
                model = model,
                api_key = apiKey,
                language_code = languageCode.orEmpty(),
                base_url = baseUrl.orEmpty(),
                timeout_ms = timeoutMs ?: 0,
            )
    }

    /** Look up a previously registered model by id. */
    @JvmStatic
    fun lookup(id: String): CloudModelEntry? = registry[id]

    /** True iff a model is registered under [id]. */
    @JvmStatic
    fun isRegistered(id: String): Boolean = registry.containsKey(id)

    /** Remove the model registered under [id]. Returns true when an entry was removed. */
    @JvmStatic
    fun unregisterModel(id: String): Boolean = registry.remove(id) != null

    /** Remove every registered model entry. */
    @JvmStatic
    fun clear() {
        registry.clear()
    }

    // Developer-defined providers

    // Kept by name so re-registration and [unregisterProvider] are
    // well-defined. The native side holds the authoritative GlobalRef; this
    // map mirrors it for lifecycle clarity.
    private val providerHandlers = ConcurrentHashMap<String, NativeCloudSttProvider>()

    /**
     * Register (or replace) a developer-defined cloud STT provider under
     * [name]. The [handler] performs the whole request host-side (build +
     * HTTP + parse), so any vendor works without a native adapter. Tie a
     * model to it by calling [register] with the same `provider` string:
     *
     *     Cloud.registerProvider("deepgram") { req ->
     *         // build + POST with OkHttp, parse the JSON …
     *         CloudSttResult(text = transcript, confidence = score)
     *     }
     *     Cloud.register(
     *         id = "dg-nova2", provider = "deepgram", model = "nova-2",
     *         apiKey = "…", baseUrl = "https://api.deepgram.com",
     *     )
     *
     * The handler is invoked on the router's request thread and may block on
     * network. Built-in providers (e.g. "sarvam") cannot be shadowed — a
     * static adapter always wins over a host callback of the same name.
     *
     * @throws IllegalArgumentException if [name] is blank.
     * @throws IllegalStateException if native registration fails.
     */
    @JvmStatic
    fun registerProvider(
        name: String,
        handler: CloudSttProvider,
    ) {
        require(name.isNotBlank()) { "Cloud provider name must be non-blank" }
        val native = NativeCloudSttProvider(handler)
        val rc = RunAnywhereBridge.racCloudRegisterSttProvider(name, native)
        check(rc == RunAnywhereBridge.RAC_SUCCESS) {
            "Failed to register cloud provider '$name' (rc=$rc)"
        }
        providerHandlers[name] = native
    }

    /**
     * Remove a developer-defined provider previously registered via
     * [registerProvider]. Idempotent for unknown names.
     */
    @JvmStatic
    fun unregisterProvider(name: String) {
        if (name.isBlank()) {
            return
        }
        RunAnywhereBridge.racCloudUnregisterSttProvider(name)
        providerHandlers.remove(name)
    }

    // Config JSON

    /**
     * Build the config JSON the routed "cloud" plugin's `create` expects from
     * a registered entry. Carries `provider` so the engine selects the right
     * HTTP backend. Internal — the router uses this to create the online
     * service. Mirrors Swift's `Cloud.configJSON(for:)`.
     *
     * @throws SDKException when no model is registered under [id].
     */
    internal fun configJson(id: String): String {
        val entry =
            lookup(id) ?: throw SDKException.invalidArgument(
                "Cloud model id '$id' not registered. " +
                    "Call Cloud.register(id, provider, model, apiKey) at app startup.",
            )
        // snake_case keys: the cloud_stt engine reads snake_case out of the
        // config_json blob (provider / api_key / model / language_code /
        // base_url / timeout_ms). The generated Wire JSON encoder emits
        // camelCase per the proto jsonName, which the engine does NOT
        // understand — so build the snake_case object explicitly here.
        // Optional fields at their proto default are omitted so the provider
        // auto-detects (language) / uses its own defaults (base URL / timeout).
        val json =
            JSONObject()
                .put("provider", entry.provider)
                .put("api_key", entry.api_key)
                .put("model", entry.model)
        if (entry.language_code.isNotEmpty()) json.put("language_code", entry.language_code)
        if (entry.base_url.isNotEmpty()) json.put("base_url", entry.base_url)
        if (entry.timeout_ms != 0) json.put("timeout_ms", entry.timeout_ms)
        return json.toString()
    }
}
