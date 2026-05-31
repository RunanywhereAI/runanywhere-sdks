package com.runanywhere.sdk.foundation.constants

/**
 * SDK-wide constants (metadata only).
 *
 * Mirrors Swift's `SDKConstants` (canonical source of truth at
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift`).
 *
 * Capability-specific constants live in their respective capability packages
 * (e.g. LLM, Storage, Download, Lifecycle, Registry).
 *
 * The value of [VERSION] must track the canonical `sdk/runanywhere-commons/VERSION`
 * file — see `scripts/release/sync-versions.sh`.
 *
 * Platform discrimination is handled by KMP source sets (jvmMain / androidMain),
 * so no `platform` constant is exposed here — that's a Swift-only concern.
 */
object SDKConstants {
    /** Canonical SDK version; mirrors `sdk/runanywhere-commons/VERSION`. */
    const val VERSION = "0.19.13"

    /** Alias for [VERSION] to match the cross-SDK `sdkVersion` naming. */
    const val SDK_VERSION = VERSION

    /** SDK name. Matches Swift's `SDKConstants.name`. */
    const val SDK_NAME = "RunAnywhere SDK"

    /** HTTP User-Agent header value. Mirrors Swift's `SDKConstants.userAgent`. */
    val USER_AGENT get() = "$SDK_NAME/$VERSION (Kotlin)"

    /** Minimum log level in production. Mirrors Swift's `SDKConstants.productionLogLevel`. */
    const val PRODUCTION_LOG_LEVEL = "error"

    /** Platform identifier hoisted from formerly hardcoded sites in CppBridge/CppBridgeAuth/CppBridgeTelemetry/CppBridgeState. */
    const val SDK_PLATFORM: String = "android"
}
