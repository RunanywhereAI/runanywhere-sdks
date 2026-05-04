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

package com.runanywhere.sdk.public

/**
 * SDK environment mode — determines how data is handled.
 *
 * Use the proto enum cases directly:
 * - `SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT`
 * - `SDKEnvironment.SDK_ENVIRONMENT_STAGING`
 * - `SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION`
 */
typealias SDKEnvironment = ai.runanywhere.proto.v1.SDKEnvironment

// ════════════════════════════════════════════════════════════════════════════
// Extensions (preserved from the hand-written enum)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Lowercase wire string ("development" / "staging" / "production" /
 * "unspecified"). Used by Sentry tags, log-line tags, and any other
 * identifier that wants the short case name rather than the proto prefix.
 */
val SDKEnvironment.wireString: String
    get() =
        when (this) {
            SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT -> "development"
            SDKEnvironment.SDK_ENVIRONMENT_STAGING -> "staging"
            SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION -> "production"
            SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED -> "unspecified"
        }

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

/**
 * Parse a wire-format string back into the proto enum. Case-insensitive.
 * Returns null on unknown inputs.
 */
fun sdkEnvironmentFromWireString(value: String): SDKEnvironment? =
    when (value.lowercase()) {
        "development" -> SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
        "staging" -> SDKEnvironment.SDK_ENVIRONMENT_STAGING
        "production" -> SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
        else -> null
    }
