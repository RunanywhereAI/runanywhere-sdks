package com.runanywhere.sdk.utils

/**
 * SDK Constants
 *
 * Canonical identity fields only. The value of [VERSION] must track the
 * canonical `sdk/runanywhere-commons/VERSION` file — see `scripts/sync-versions.sh`.
 */
object SDKConstants {
    /** Canonical SDK version; mirrors `sdk/runanywhere-commons/VERSION`. */
    const val VERSION = "0.19.13"

    /** Alias for [VERSION] to match core.SDKConstants naming across SDKs. */
    const val SDK_VERSION = VERSION

    /** SDK identifier used in telemetry / user-agent strings. */
    const val SDK_NAME = "runanywhere-kotlin"

    /** HTTP User-Agent header value. */
    val USER_AGENT get() = "RunAnywhere-Kotlin-SDK/$VERSION"
}
