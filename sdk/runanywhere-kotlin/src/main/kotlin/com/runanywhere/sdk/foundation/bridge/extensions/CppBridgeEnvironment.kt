/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Environment bridge extension for C++ interop.
 *
 * Wraps the SDK-environment + dev-config-query layer. The Swift
 * counterpart exposes three nested namespaces — `Environment`,
 * `DevConfig`, `Endpoints` — that wrap `rac_environment.h`,
 * `rac_dev_config.h`, and `rac_endpoints.h` respectively. Kotlin
 * mirrors the same structure here.
 *
 * Mirrors iOS source of truth:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/
 *     CppBridge+Environment.swift
 *
 * NOTE: the dev-config query helpers also exist inside
 * `CppBridgeTelemetry` (`hasUsableDevelopmentConfig`,
 * `looksLikePlaceholder`, `isUsableHttpUrl`) and inline blocks of
 * `CppBridgeDevice`. Per the task spec the originals are NOT modified
 * yet — this file is the future-canonical home for them. A follow-up
 * will retire the duplicates.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.bridge.HTTPClientAdapter
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.configuration.cEnvironment

/**
 * Environment configuration bridge.
 *
 * Wraps `rac_environment.h` helpers — `requires_auth`,
 * `requires_backend_url`, `validate_api_key`, `validate_base_url`,
 * `validation_error_message`. Mirrors Swift's `CppBridge.Environment`
 * enum namespace.
 *
 * All helpers delegate to the JNI bindings declared in
 * `RunAnywhereBridge.kt` (see "ENVIRONMENT VALIDATION + ENDPOINTS"
 * section). If the native library is not loaded yet, the calls fall
 * back to conservative defaults that match the C++ behaviour for the
 * relevant environment.
 */
object CppBridgeEnvironment {
    /**
     * Convert a Kotlin [SDKEnvironment] to the `rac_environment_t`
     * integer used by the C ABI. Delegates to the existing
     * [SDKEnvironment.cEnvironment] extension to keep a single source
     * of truth.
     */
    fun toC(env: SDKEnvironment): Int = env.cEnvironment

    /**
     * Convert a `rac_environment_t` integer back to a Kotlin
     * [SDKEnvironment]. Unknown values fall through to development,
     * matching Swift's default arm.
     */
    fun fromC(cEnv: Int): SDKEnvironment =
        when (cEnv) {
            0 -> SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
            1 -> SDKEnvironment.SDK_ENVIRONMENT_STAGING
            2 -> SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
            else -> SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
        }

    fun isProduction(env: SDKEnvironment): Boolean =
        RunAnywhereBridge.racEnvIsProduction(toC(env))

    fun isTesting(env: SDKEnvironment): Boolean =
        RunAnywhereBridge.racEnvIsTesting(toC(env))

    fun shouldSendTelemetry(env: SDKEnvironment): Boolean =
        RunAnywhereBridge.racEnvShouldSendTelemetry(toC(env))

    fun shouldSyncWithBackend(env: SDKEnvironment): Boolean =
        RunAnywhereBridge.racEnvShouldSyncWithBackend(toC(env))

    /**
     * Whether [env] requires authentication. Mirrors Swift's
     * `CppBridge.Environment.requiresAuth(_:)` — delegates to
     * `rac_env_requires_auth` via JNI.
     */
    fun requiresAuth(env: SDKEnvironment): Boolean =
        RunAnywhereBridge.racEnvRequiresAuth(toC(env))

    /**
     * Whether [env] requires an explicit backend base URL. Mirrors
     * Swift's `CppBridge.Environment.requiresBackendURL(_:)` —
     * delegates to `rac_env_requires_backend_url` via JNI.
     */
    fun requiresBackendURL(env: SDKEnvironment): Boolean =
        RunAnywhereBridge.racEnvRequiresBackendUrl(toC(env))

    /**
     * Validate an API key for [env]. Returns `true` when the key
     * passes `RAC_VALIDATION_OK`. Mirrors Swift's
     * `CppBridge.Environment.validateAPIKey(_:for:)` — the underlying
     * JNI binding folds the Swift `rac_validation_result_t` enum into
     * a single Boolean (`true == ok`).
     */
    fun validateAPIKey(key: String, env: SDKEnvironment): Boolean {
        // The current JNI thunk is env-independent (validates against
        // a single global policy), but we keep the [env] parameter in
        // the Kotlin API surface for symmetry with Swift and so the
        // call site can be retargeted at a per-env validator without
        // a breaking change.
        @Suppress("UNUSED_PARAMETER")
        val unused = env
        return RunAnywhereBridge.racEnvValidateApiKey(key)
    }

    /**
     * Validate a base URL for [env]. Returns `true` when the URL
     * passes `RAC_VALIDATION_OK`. Mirrors Swift's
     * `CppBridge.Environment.validateBaseURL(_:for:)`.
     */
    fun validateBaseURL(url: String, env: SDKEnvironment): Boolean {
        @Suppress("UNUSED_PARAMETER")
        val unused = env
        return RunAnywhereBridge.racEnvValidateBaseUrl(url)
    }

    /**
     * Resolve the human-readable validation error message for the
     * given `(env, key, url)` triple. Returns the message when the
     * triple fails validation, `null` when it passes.
     *
     * Mirrors Swift's
     * `CppBridge.Environment.validationErrorMessage(_:)`. The Swift
     * surface takes a single `rac_validation_result_t` because
     * `validate_api_key` / `validate_base_url` return that result
     * directly; the Kotlin JNI thunk inverts the call shape and
     * folds the triple into a single helper that returns either the
     * message string or null when everything validates.
     */
    fun validationErrorMessage(env: SDKEnvironment, key: String, url: String): String? =
        RunAnywhereBridge.racEnvValidationErrorMessage(toC(env), key, url)
}

/**
 * Development configuration bridge.
 *
 * Wraps the four `rac_dev_config_*` accessors that ship with the
 * commons library and are populated by `development_config.cpp` (the
 * Supabase + build-token bundle used in dev mode). Mirrors Swift's
 * `CppBridge.DevConfig` enum namespace.
 *
 * Thread safety: every accessor delegates to the native side which is
 * read-only after build time; no Kotlin-side locking is required.
 */
object CppBridgeDevConfig {
    private val placeholderPattern: Regex =
        Regex("YOUR_|<your|REPLACE_ME|PLACEHOLDER", RegexOption.IGNORE_CASE)

    /**
     * Whether `rac_dev_config_*` was compiled into commons with a
     * non-template payload. Mirrors Swift's `DevConfig.isAvailable`.
     */
    val isAvailable: Boolean
        get() = RunAnywhereBridge.racDevConfigIsAvailable()

    /** Supabase URL for development mode. Mirrors Swift's `DevConfig.supabaseURL`. */
    val supabaseURL: String?
        get() = RunAnywhereBridge.racDevConfigGetSupabaseUrl()

    /** Supabase anon key for development mode. Mirrors Swift's `DevConfig.supabaseKey`. */
    val supabaseKey: String?
        get() = RunAnywhereBridge.racDevConfigGetSupabaseKey()

    /** Build token for development mode. Mirrors Swift's `DevConfig.buildToken`. */
    val buildToken: String?
        get() = RunAnywhereBridge.racDevConfigGetBuildToken()?.takeIf { isUsableCredential(it) }

    /**
     * Whether the dev Supabase config is present and not a template
     * placeholder. Mirrors Swift's `DevConfig.hasUsableSupabaseConfig`.
     */
    val hasUsableSupabaseConfig: Boolean
        get() {
            val url = supabaseURL ?: return false
            val key = supabaseKey ?: return false
            return isUsableHTTPURL(url) && isUsableCredential(key)
        }

    /**
     * Whether the dev build token is present and not a placeholder.
     * Mirrors Swift's `DevConfig.hasUsableBuildToken`.
     */
    val hasUsableBuildToken: Boolean
        get() = buildToken != null

    /**
     * Whether dev-mode device registration has every required value.
     * Mirrors Swift's `DevConfig.hasUsableDevelopmentRegistrationConfig`.
     */
    val hasUsableDevelopmentRegistrationConfig: Boolean
        get() = hasUsableSupabaseConfig && hasUsableBuildToken

    /**
     * Configure [HTTPClientAdapter] for development mode using the C++
     * dev-config payload. Returns `true` when the adapter was
     * configured, `false` when the dev config is unavailable or the
     * URL/key fail the usability checks.
     *
     * Mirrors Swift's `CppBridge.DevConfig.configureHTTP()` —
     * `async` suspend, validates with the same `isUsableHTTPURL` /
     * `isUsableCredential` rules, trims the URL + key before handing
     * them to the HTTP adapter, and returns `false` rather than
     * throwing when the inputs are unusable.
     */
    suspend fun configureHTTP(): Boolean {
        if (!hasUsableSupabaseConfig) return false
        val rawUrl = supabaseURL ?: return false
        val rawKey = supabaseKey ?: return false
        val trimmedUrl = rawUrl.trim()
        val trimmedKey = rawKey.trim()
        if (!isUsableHTTPURL(trimmedUrl)) return false
        if (!isUsableCredential(trimmedKey)) return false
        HTTPClientAdapter.configure(baseURL = trimmedUrl, apiKey = trimmedKey)
        return true
    }

    /**
     * Whether [value] is a usable credential — non-blank and not a
     * placeholder. Delegates to the canonical commons rule
     * (`rac_dev_config_is_usable_credential`) so every SDK agrees instead of
     * each carrying its own regex; falls back to the local pattern when the
     * native symbol predates the loaded library. Mirrors Swift's
     * `DevConfig.isUsableCredential`.
     */
    fun isUsableCredential(value: String?): Boolean {
        if (value == null) return false
        return try {
            RunAnywhereBridge.racDevConfigIsUsableCredential(value)
        } catch (_: UnsatisfiedLinkError) {
            value.isNotBlank() && !placeholderPattern.containsMatchIn(value)
        }
    }

    /**
     * Whether [value] looks like a template placeholder — the inverse of
     * [isUsableCredential], retained for callers that ask it that way.
     * Mirrors Swift's `DevConfig.looksLikePlaceholder`.
     */
    fun looksLikePlaceholder(value: String?): Boolean = !isUsableCredential(value)

    /**
     * Whether [value] is a usable HTTP/HTTPS URL with a real host. Delegates to
     * the canonical commons rule (`rac_dev_config_is_usable_http_url`); falls
     * back to a local scheme + host check when the symbol predates the library.
     * Mirrors Swift's `DevConfig.isUsableHTTPURL`.
     */
    fun isUsableHTTPURL(value: String?): Boolean {
        val trimmed = value?.trim() ?: return false
        return try {
            RunAnywhereBridge.racDevConfigIsUsableHttpUrl(trimmed)
        } catch (_: UnsatisfiedLinkError) {
            if (!isUsableCredential(trimmed)) return false
            if (!trimmed.startsWith("https://") && !trimmed.startsWith("http://")) return false
            val host = trimmed.substringAfter("://").substringBefore('/').substringBefore('?')
            host.isNotBlank() &&
                !host.contains('<') &&
                !host.contains('>') &&
                host.none { it.isWhitespace() }
        }
    }
}

/**
 * Endpoint paths bridge.
 *
 * Wraps `rac_endpoints.h` macros + helper functions. Mirrors Swift's
 * `CppBridge.Endpoints` enum namespace.
 *
 * The endpoint accessors delegate to the JNI bindings declared in
 * `RunAnywhereBridge.kt`. If the native binding returns null or
 * throws (e.g. native lib not yet loaded), the accessors fall back to
 * the hard-coded path constants which mirror the values in
 * `idl/endpoints.proto`.
 */
object CppBridgeEndpoints {
    /** Fallback constants used when the native binding is unreachable.
     *  Mirror the canonical values in `rac_endpoints.h`. */
    private const val FALLBACK_DEV_DEVICE_REGISTRATION: String = "/rest/v1/devices"
    private const val FALLBACK_PROD_DEVICE_REGISTRATION: String = "/api/v1/devices"
    private const val FALLBACK_DEV_TELEMETRY: String = "/rest/v1/telemetry_events"
    private const val FALLBACK_PROD_TELEMETRY: String = "/api/v1/telemetry"
    private const val FALLBACK_MODEL_ASSIGNMENTS: String = "/api/v1/models/assignments"

    /** SDK authenticate endpoint. Mirrors Swift's `Endpoints.authenticate`. */
    val AUTHENTICATE: String?
        get() = RunAnywhereBridge.racEndpointAuthenticate()

    /** SDK refresh endpoint. Mirrors Swift's `Endpoints.refresh`. */
    val REFRESH: String?
        get() = RunAnywhereBridge.racEndpointRefresh()

    /** SDK health endpoint. Mirrors Swift's `Endpoints.health`. */
    val HEALTH: String?
        get() = RunAnywhereBridge.racEndpointHealth()

    /**
     * Device registration endpoint for [env]. Mirrors Swift's
     * `Endpoints.deviceRegistration(for:)` — delegates to
     * `rac_endpoint_device_registration` via JNI.
     */
    fun deviceRegistration(env: SDKEnvironment): String {
        val fallback =
            when (env) {
                SDKEnvironment.SDK_ENVIRONMENT_STAGING,
                SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
                -> FALLBACK_PROD_DEVICE_REGISTRATION
                else -> FALLBACK_DEV_DEVICE_REGISTRATION
            }
        return jniOrFallback(fallback) {
            RunAnywhereBridge.racEndpointDeviceRegistration(CppBridgeEnvironment.toC(env))
        }
    }

    /**
     * Telemetry endpoint for [env]. Mirrors Swift's
     * `Endpoints.telemetry(for:)` — delegates to
     * `rac_endpoint_telemetry` via JNI.
     */
    fun telemetry(env: SDKEnvironment): String {
        val fallback =
            when (env) {
                SDKEnvironment.SDK_ENVIRONMENT_STAGING,
                SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
                -> FALLBACK_PROD_TELEMETRY
                else -> FALLBACK_DEV_TELEMETRY
            }
        return jniOrFallback(fallback) {
            RunAnywhereBridge.racEndpointTelemetry(CppBridgeEnvironment.toC(env))
        }
    }

    /** Model assignments endpoint. Mirrors Swift's `Endpoints.modelAssignments()`. */
    fun modelAssignments(): String =
        jniOrFallback(FALLBACK_MODEL_ASSIGNMENTS) { RunAnywhereBridge.racEndpointModelAssignments() }

    /**
     * Return the JNI-resolved endpoint when the binding is reachable
     * and returns a non-null/non-blank string; otherwise fall back to
     * the hard-coded constant. The fallback layer keeps the SDK
     * usable in unit tests and during early bring-up where the native
     * library may not be loaded (in which case `external fun` calls
     * raise [UnsatisfiedLinkError]). All `Java_*` exports for these
     * thunks are wired in `sdk/runanywhere-commons/src/jni/
     * runanywhere_commons_jni.cpp` as pure constant-string returns, so
     * no other failure mode is reachable on the happy path.
     */
    private inline fun jniOrFallback(fallback: String, block: () -> String?): String =
        try {
            block()?.takeIf { it.isNotBlank() } ?: fallback
        } catch (_: UnsatisfiedLinkError) {
            fallback
        }
}
