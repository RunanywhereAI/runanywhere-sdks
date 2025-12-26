package com.runanywhere.sdk.foundation

import android.util.Log

/**
 * Android implementation of PlatformLogger using Android Log
 */
actual class PlatformLogger actual constructor(
    private val tag: String,
) {
    actual fun debug(message: String) {
        Log.d(tag, message)
    }

    actual fun info(message: String) {
        Log.i(tag, message)
    }

    actual fun warning(message: String) {
        Log.w(tag, message)
    }

    actual fun error(
        message: String,
        throwable: Throwable?,
    ) {
        if (throwable != null) {
            Log.e(tag, message, throwable)
        } else {
            Log.e(tag, message)
        }
    }
}
