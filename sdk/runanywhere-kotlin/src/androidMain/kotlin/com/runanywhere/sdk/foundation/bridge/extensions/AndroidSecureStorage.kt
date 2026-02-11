/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android-specific secure storage implementation using SharedPreferences.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64

/**
 * Android implementation of PlatformSecureStorage using SharedPreferences.
 *
 * @param context The Android application context
 */
class AndroidSecureStorage(
    context: Context,
) : CppBridgePlatformAdapter.PlatformSecureStorage {
    private val sharedPreferences: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    companion object {
        private const val PREFS_NAME = "runanywhere_secure_storage"
    }

    override fun get(key: String): ByteArray? {
        val base64Value = sharedPreferences.getString(key, null) ?: return null
        return Base64.decode(base64Value, Base64.NO_WRAP)
    }

    override fun set(key: String, value: ByteArray): Boolean {
        val base64Value = Base64.encodeToString(value, Base64.NO_WRAP)
        sharedPreferences.edit().putString(key, base64Value).apply()
        return true
    }

    override fun delete(key: String): Boolean {
        sharedPreferences.edit().remove(key).apply()
        return true
    }

    override fun clear() {
        sharedPreferences.edit().clear().apply()
    }
}

/**
 * Extension function to easily set Android context for CppBridgePlatformAdapter.
 * This is the recommended way to initialize storage on Android.
 *
 * @param context The Android context (will use applicationContext internally)
 */
fun CppBridgePlatformAdapter.setContext(context: Context) {
    setPlatformStorage(AndroidSecureStorage(context))
}
