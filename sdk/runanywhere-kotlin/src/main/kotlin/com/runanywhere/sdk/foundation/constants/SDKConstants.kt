package com.runanywhere.sdk.foundation.constants

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * SDK-wide constants (metadata only).
 *
 * Mirrors Swift's `SDKConstants` (canonical source of truth at
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift`,
 * whose `version` reads `rac_sdk_get_version()` from commons).
 *
 * Capability-specific constants live in their respective capability packages
 * (e.g. LLM, Storage, Download, Lifecycle, Registry).
 */
object SDKConstants {
    /**
     * Pre-load fallback for [VERSION]. Mirrors the canonical
     * `sdk/runanywhere-commons/VERSION` file; the `const val VERSION` literal
     * below is rewritten on every release by `scripts/release/sync-versions.sh`.
     */
    private object Fallback {
        const val VERSION = "0.20.0"
    }

    /**
     * Canonical SDK version. Resolved once, at first access, from commons
     * (`rac_sdk_get_version()` via JNI) when the native library is loaded;
     * falls back to the hardcoded [Fallback.VERSION] mirror otherwise (e.g.
     * native library absent, or paired with an older `.so` that predates the
     * `racSdkGetVersion` export).
     */
    val VERSION: String by lazy { nativeVersionOrNull() ?: Fallback.VERSION }

    /** Alias for [VERSION] to match the cross-SDK `sdkVersion` naming. */
    val SDK_VERSION: String get() = VERSION

    /** SDK name. Matches Swift's `SDKConstants.name`. */
    const val SDK_NAME = "RunAnywhere SDK"

    /** HTTP User-Agent header value. Mirrors Swift's `SDKConstants.userAgent`. */
    val USER_AGENT get() = "$SDK_NAME/$VERSION (Kotlin)"

    /** Minimum log level in production. Mirrors Swift's `SDKConstants.productionLogLevel`. */
    const val PRODUCTION_LOG_LEVEL = "error"

    /** Platform identifier hoisted from formerly hardcoded sites in CppBridge/CppBridgeAuth/CppBridgeTelemetry/CppBridgeState. */
    const val SDK_PLATFORM: String = "android"

    private fun nativeVersionOrNull(): String? =
        try {
            if (RunAnywhereBridge.isNativeLibraryLoaded()) {
                RunAnywhereBridge.racSdkGetVersion()?.takeIf { it.isNotBlank() }
            } else {
                null
            }
        } catch (_: UnsatisfiedLinkError) {
            // Older native binary without the racSdkGetVersion export.
            null
        }
}
