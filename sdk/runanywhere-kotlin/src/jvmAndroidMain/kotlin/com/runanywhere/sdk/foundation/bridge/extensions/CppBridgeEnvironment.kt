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
 * NOTE (B18): the dev-config query helpers also exist inside
 * `CppBridgeTelemetry` (`hasUsableDevelopmentConfig`,
 * `looksLikePlaceholder`, `isUsableHttpUrl`) and inline blocks of
 * `CppBridgeDevice`. Per the task spec the originals are NOT modified
 * yet — this file is the future-canonical home for them. A follow-up
 * will retire the duplicates.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

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
 * TODO(KOT-B18): no `racEnvRequiresAuth` / `racValidateApiKey` /
 * `racValidateBaseUrl` / `racValidationErrorMessage` external funs are
 * declared in `RunAnywhereBridge.kt` yet. Each accessor below
 * therefore returns a conservative default that matches the C++
 * behaviour for the relevant environment. When the commons follow-up
 * exposes those calls over JNI, swap the bodies for direct delegation
 * to `RunAnywhereBridge.*`.
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

    /**
     * Whether [env] requires authentication. Production and staging
     * always do; development is permissive.
     *
     * TODO(KOT-B18): replace with `RunAnywhereBridge.racEnvRequiresAuth(...)`
     * once that JNI binding lands.
     */
    fun requiresAuth(env: SDKEnvironment): Boolean =
        env == SDKEnvironment.SDK_ENVIRONMENT_STAGING ||
            env == SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION

    /**
     * Whether [env] requires an explicit backend base URL (vs falling
     * back to the development default). Production and staging do.
     *
     * TODO(KOT-B18): replace with
     * `RunAnywhereBridge.racEnvRequiresBackendUrl(...)` once that JNI
     * binding lands.
     */
    fun requiresBackendURL(env: SDKEnvironment): Boolean = requiresAuth(env)
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
        get() =
            try {
                RunAnywhereBridge.racDevConfigIsAvailable()
            } catch (_: Throwable) {
                false
            }

    /** Supabase URL for development mode. Mirrors Swift's `DevConfig.supabaseURL`. */
    val supabaseURL: String?
        get() =
            try {
                RunAnywhereBridge.racDevConfigGetSupabaseUrl()
            } catch (_: Throwable) {
                null
            }

    /** Supabase anon key for development mode. Mirrors Swift's `DevConfig.supabaseKey`. */
    val supabaseKey: String?
        get() =
            try {
                RunAnywhereBridge.racDevConfigGetSupabaseKey()
            } catch (_: Throwable) {
                null
            }

    /** Build token for development mode. Mirrors Swift's `DevConfig.buildToken`. */
    val buildToken: String?
        get() =
            try {
                RunAnywhereBridge.racDevConfigGetBuildToken()?.takeIf { isUsableCredential(it) }
            } catch (_: Throwable) {
                null
            }

    /** Sentry DSN for crash reporting (optional). Mirrors Swift's `DevConfig.sentryDSN`. */
    val sentryDSN: String?
        get() =
            try {
                RunAnywhereBridge.racDevConfigGetSentryDsn()
            } catch (_: Throwable) {
                null
            }

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
     * Whether [value] looks like a template placeholder. Matches the
     * regex Swift uses in `DevConfig.looksLikePlaceholder`.
     */
    fun looksLikePlaceholder(value: String?): Boolean {
        if (value.isNullOrBlank()) return true
        return placeholderPattern.containsMatchIn(value)
    }

    /**
     * Whether [value] is a usable credential — non-blank and not a
     * placeholder. Mirrors Swift's `DevConfig.isUsableCredential`.
     */
    fun isUsableCredential(value: String?): Boolean = !looksLikePlaceholder(value)

    /**
     * Whether [value] is a usable HTTP/HTTPS URL with a real host.
     * Mirrors Swift's `DevConfig.isUsableHTTPURL`.
     */
    fun isUsableHTTPURL(value: String?): Boolean {
        val trimmed = value?.trim() ?: return false
        if (looksLikePlaceholder(trimmed)) return false
        if (!trimmed.startsWith("https://") && !trimmed.startsWith("http://")) return false
        // Strip scheme + any path/query, leaving the host.
        val schemeStripped = trimmed.substringAfter("://")
        val host = schemeStripped.substringBefore('/').substringBefore('?')
        if (host.isBlank()) return false
        if (host.contains('<') || host.contains('>')) return false
        if (host.any { it.isWhitespace() }) return false
        return true
    }
}

/**
 * Endpoint paths bridge.
 *
 * Wraps `rac_endpoints.h` macros + helper functions. Mirrors Swift's
 * `CppBridge.Endpoints` enum namespace.
 *
 * TODO(KOT-B18): the matching `racEndpoint*` external funs aren't
 * declared in `RunAnywhereBridge.kt` yet. The hard-coded path constants
 * mirror the values in `idl/endpoints.proto` so existing callers keep
 * working; once the JNI bindings land, swap each accessor for a direct
 * delegation to the C ABI.
 */
object CppBridgeEndpoints {

    /** SDK authenticate endpoint. Mirrors Swift's `Endpoints.authenticate`. */
    const val AUTHENTICATE: String = "/api/v1/auth/sdk/authenticate"

    /** SDK refresh endpoint. Mirrors Swift's `Endpoints.refresh`. */
    const val REFRESH: String = "/api/v1/auth/sdk/refresh"

    /** SDK health endpoint. Mirrors Swift's `Endpoints.health`. */
    const val HEALTH: String = "/api/v1/health"

    /**
     * Device registration endpoint for [env]. Production and staging
     * share the same Railway path; development uses the Supabase REST
     * `devices` table.
     */
    fun deviceRegistration(env: SDKEnvironment): String =
        when (env) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> "/rest/v1/devices"
            SDKEnvironment.SDK_ENVIRONMENT_STAGING,
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
            -> "/api/v1/devices"
            SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> "/rest/v1/devices"
        }

    /**
     * Telemetry endpoint for [env]. Mirrors Swift's
     * `Endpoints.telemetry(for:)`.
     */
    fun telemetry(env: SDKEnvironment): String =
        when (env) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> "/rest/v1/telemetry_events"
            SDKEnvironment.SDK_ENVIRONMENT_STAGING,
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
            -> "/api/v1/telemetry"
            SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> "/rest/v1/telemetry_events"
        }

    /** Model assignments endpoint. Mirrors Swift's `Endpoints.modelAssignments()`. */
    fun modelAssignments(): String = "/api/v1/models/assignments"
}
