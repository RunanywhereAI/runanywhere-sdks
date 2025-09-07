package com.runanywhere.sdk.core

/**
 * SDK-wide constants
 */
object SDKConstants {
    /**
     * Current SDK version
     * This should be updated with each release
     */
    const val SDK_VERSION = "0.1.0"

    /**
     * SDK name for telemetry and identification
     */
    const val SDK_NAME = "RunAnywhere KMP SDK"

    /**
     * Default timeout values (in milliseconds)
     */
    object Timeouts {
        const val DEFAULT_NETWORK_TIMEOUT = 30_000L
        const val DEFAULT_DOWNLOAD_TIMEOUT = 300_000L
        const val DEFAULT_MODEL_LOAD_TIMEOUT = 60_000L
    }

    /**
     * Default configuration values
     */
    object Defaults {
        const val DEFAULT_MAX_RETRIES = 3
        const val DEFAULT_BATCH_SIZE = 100
        const val DEFAULT_CACHE_SIZE_MB = 500
    }
}
