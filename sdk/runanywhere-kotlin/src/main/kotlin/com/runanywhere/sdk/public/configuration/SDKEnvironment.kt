/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * SDK environment mode — determines how data is handled.
 *
 * §15 (CANONICAL_API.md): `SDKEnvironment` is a typealias for the proto3-generated
 * `ai.runanywhere.proto.v1.SDKEnvironment` (idl/model_types.proto). The hand-written
 * enum that previously lived in `RunAnywhere.kt` (with `toProto()`/`fromProto()`
 * bijections) has been removed — a single source of truth now lives in the IDL.
 * All helper behaviour that callers relied on (wire string, legacy C-ABI int,
 * deployable-cases list) is preserved as extensions.
 *
 * Mirrors Swift's `SDKEnvironment.swift` typealias pattern.
 */

package com.runanywhere.sdk.public.configuration

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEnvironment
import com.runanywhere.sdk.foundation.errors.SDKException

/**
 * SDK environment mode — determines how data is handled.
 *
 * Use the proto enum cases directly:
 * - `SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT`
 * - `SDKEnvironment.SDK_ENVIRONMENT_STAGING`
 * - `SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION`
 */
typealias SDKEnvironment = ai.runanywhere.proto.v1.SDKEnvironment

// Extensions (preserved from the hand-written enum)
//
// `wireString` and the reverse `fromWireString` factory are emitted by the
// convenience codegen (see `generated/convenience/RAConvenience.kt`) — the
// hand-written drift was retired in T6.4. Import them from
// `com.runanywhere.sdk.generated.convenience` (extension property +
// `Companion.fromWireString` factory).

/**
 * Legacy C-ABI integer (0 = development, 1 = staging, 2 = production).
 * Kept so the JNI `rac_environment_t` mapping continues to compile
 * unchanged; new code should prefer `toString()` / `wireString` instead.
 */
val SDKEnvironment.cEnvironment: Int
    get() =
        when (this) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> 0
            SDKEnvironment.SDK_ENVIRONMENT_STAGING -> 1
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION -> 2
            SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> 0
        }

/** Human-readable description, matching Swift's `description` string. */
val SDKEnvironment.description: String
    get() =
        when (this) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> "Development Environment"
            SDKEnvironment.SDK_ENVIRONMENT_STAGING -> "Staging Environment"
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION -> "Production Environment"
            SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> "Unspecified Environment"
        }

// SDKInitParams — mirrors Swift's `SDKInitParams` struct (3 constructors +
// validate). Kotlin uses `String` for `baseURL` (no commonMain URL type;
// matches the existing `RunAnywhere.initialize(baseURL: String?)` shape).

/**
 * SDK initialization parameters.
 *
 * Mirrors Swift's `SDKInitParams` struct
 * (`sdk/runanywhere-swift/Sources/RunAnywhere/Public/Configuration/SDKEnvironment.swift`):
 *
 * - [apiKey] — backend API key for authentication.
 * - [baseURL] — backend API base URL. Required for staging/production; a
 *   development placeholder is used when the development convenience
 *   constructor is invoked.
 * - [environment] — environment mode (development/staging/production).
 * - [deviceId] — optional override for the device identifier; null lets the
 *   SDK derive the value from the platform identifier or persisted Keychain
 *   entry.
 *
 * All three Swift convenience initializers are surfaced as Kotlin factories
 * on the companion object so the call shape mirrors Swift line-for-line.
 */
data class SDKInitParams(
    val apiKey: String,
    val baseURL: String,
    val environment: SDKEnvironment,
    val deviceId: String? = null,
) {
    companion object {
        /**
         * Placeholder URL used for development when no URL is provided.
         * Development mode uses local analytics, so this is just a placeholder.
         * Mirrors Swift's `developmentPlaceholderURL`.
         */
        const val DEVELOPMENT_PLACEHOLDER_URL: String = "https://dev.runanywhere.local"

        /**
         * Create initialization parameters for staging or production. Throws
         * [SDKException] when [apiKey] or [baseURL] fail validation against
         * the configured [environment].
         *
         * Mirrors Swift's
         * `init(apiKey:baseURL:environment:)` (URL-typed) — Kotlin folds the
         * Swift `URL` overload into the single string-typed call because
         * commonMain has no URL type.
         */
        fun create(
            apiKey: String,
            baseURL: String,
            environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
            deviceId: String? = null,
        ): SDKInitParams {
            val params =
                SDKInitParams(
                    apiKey = apiKey,
                    baseURL = baseURL,
                    environment = environment,
                    deviceId = deviceId,
                )
            params.validate()
            return params
        }

        /**
         * Convenience constructor for development mode (no URL required).
         * Mirrors Swift's `init(forDevelopmentWithAPIKey:)`.
         */
        fun forDevelopment(
            apiKey: String = "",
            deviceId: String? = null,
        ): SDKInitParams =
            SDKInitParams(
                apiKey = apiKey,
                baseURL = DEVELOPMENT_PLACEHOLDER_URL,
                environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
                deviceId = deviceId,
            )
    }

    /**
     * Validate this parameter set against the C++ validation rules. Mirrors
     * Swift's private `Self.validate(apiKey:baseURL:environment:)` — delegates
     * to `racEnvValidateApiKey`, `racEnvValidateBaseUrl`, and
     * `racEnvValidationErrorMessage` JNI thunks for cross-platform parity.
     *
     * @throws SDKException when the API key or base URL fail validation.
     */
    fun validate() {
        // Validate API key first so a missing key surfaces as `invalidApiKey`
        // rather than a generic validation failure — matches Swift's ordering.
        if (!sdkInitParamsValidateApiKey(apiKey, environment)) {
            val message =
                sdkInitParamsValidationErrorMessage(environment, apiKey, baseURL)
                    ?: "Invalid API key for ${environment.description}"
            throw SDKException.invalidApiKey().let {
                SDKException(
                    error = it.error.copy(message = message),
                )
            }
        }

        if (!sdkInitParamsValidateBaseUrl(baseURL, environment)) {
            val message =
                sdkInitParamsValidationErrorMessage(environment, apiKey, baseURL)
                    ?: "Invalid base URL for ${environment.description}: $baseURL"
            throw SDKException.validationFailed(message)
        }
    }
}

internal fun sdkInitParamsValidateApiKey(key: String, env: SDKEnvironment): Boolean =
    CppBridgeEnvironment.validateAPIKey(key = key, env = env)

internal fun sdkInitParamsValidateBaseUrl(url: String, env: SDKEnvironment): Boolean =
    CppBridgeEnvironment.validateBaseURL(url = url, env = env)

internal fun sdkInitParamsValidationErrorMessage(
    env: SDKEnvironment,
    key: String,
    url: String,
): String? = CppBridgeEnvironment.validationErrorMessage(env = env, key = key, url = url)
