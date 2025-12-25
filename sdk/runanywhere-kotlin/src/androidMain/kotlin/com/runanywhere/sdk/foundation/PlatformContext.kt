package com.runanywhere.sdk.foundation

import android.content.Context
import com.runanywhere.sdk.security.AndroidSecureStorage
import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android implementation of PlatformContext
 */
actual class PlatformContext(
    private val context: Context,
) {
    actual fun initialize() {
        // Initialize platform context first
        AndroidPlatformContext.initialize(context)
        // Initialize secure storage with the same context
        AndroidSecureStorage.initialize(context)
    }
}
