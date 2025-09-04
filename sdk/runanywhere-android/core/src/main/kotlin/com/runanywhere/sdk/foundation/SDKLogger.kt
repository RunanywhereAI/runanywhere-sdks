package com.runanywhere.sdk.foundation

import android.util.Log
import com.runanywhere.sdk.data.models.LogLevel

/**
 * SDK Logger for consistent logging across the SDK
 */
class SDKLogger(private val tag: String) {

    companion object {
        private var currentLevel: LogLevel = LogLevel.INFO

        fun setLevel(level: LogLevel) {
            currentLevel = level
        }
    }

    fun debug(message: String) {
        if (currentLevel <= LogLevel.DEBUG) {
            Log.d(tag, message)
        }
    }

    fun info(message: String) {
        if (currentLevel <= LogLevel.INFO) {
            Log.i(tag, message)
        }
    }

    fun warning(message: String) {
        if (currentLevel <= LogLevel.WARNING) {
            Log.w(tag, message)
        }
    }

    fun error(message: String, throwable: Throwable? = null) {
        if (currentLevel <= LogLevel.ERROR) {
            if (throwable != null) {
                Log.e(tag, message, throwable)
            } else {
                Log.e(tag, message)
            }
        }
    }
}
