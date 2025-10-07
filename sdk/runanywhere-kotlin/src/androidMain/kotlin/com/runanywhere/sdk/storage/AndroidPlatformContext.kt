package com.runanywhere.sdk.storage

import android.content.Context

/**
 * Android-specific context holder - should be initialized by the app
 * This is shared across all Android platform implementations
 */
object AndroidPlatformContext {
    private var _applicationContext: Context? = null

    val applicationContext: Context
        get() = _applicationContext ?: throw IllegalStateException(
            "AndroidPlatformContext must be initialized with Context before use"
        )

    fun initialize(context: Context) {
        _applicationContext = context.applicationContext
    }

    fun isInitialized(): Boolean {
        return _applicationContext != null
    }

    /**
     * Get the application context (alias for applicationContext for compatibility)
     */
    fun getContext(): Context = applicationContext
}
