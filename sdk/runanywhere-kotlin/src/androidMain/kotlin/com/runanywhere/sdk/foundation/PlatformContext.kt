package com.runanywhere.sdk.foundation

import android.content.Context
import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android implementation of PlatformContext
 */
actual class PlatformContext(private val context: Context) {
    actual fun initialize() {
        AndroidPlatformContext.initialize(context)
    }
}
