/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android-specific secure storage implementation using EncryptedSharedPreferences
 * (AndroidX Security Crypto) backed by the Android Keystore (AES-256-GCM values,
 * AES-256-SIV keys, 256-bit AES-GCM master key).
 */

package com.runanywhere.sdk.foundation.security

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.infrastructure.logging.SDKLogger

/**
 * Android implementation of [CppBridgePlatformAdapter.PlatformSecureStorage] using
 * [EncryptedSharedPreferences]. Values are encrypted at rest with AES-256-GCM and
 * keys with AES-256-SIV using a master key held in the Android Keystore.
 *
 * @param context Any Android context; only [Context.getApplicationContext] is retained.
 */
class AndroidKeychainManager(
    context: Context,
) : CppBridgePlatformAdapter.PlatformSecureStorage {
    private val appContext: Context = context.applicationContext
    private val logger = SDKLogger(LOG_CATEGORY)

    private val encryptedPreferences: SharedPreferences by lazy {
        val masterKey =
            MasterKey
                .Builder(appContext)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
        EncryptedSharedPreferences.create(
            appContext,
            ENCRYPTED_PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override fun get(key: String): ByteArray? {
        val stored = encryptedPreferences.getString(key, null) ?: return null
        return Base64.decode(stored, Base64.NO_WRAP)
    }

    override fun set(key: String, value: ByteArray): Boolean {
        return try {
            encryptedPreferences
                .edit()
                .putString(key, Base64.encodeToString(value, Base64.NO_WRAP))
                .apply()
            true
        } catch (t: Throwable) {
            logger.error("Failed to write encrypted entry for key '$key': ${t.message}")
            false
        }
    }

    override fun delete(key: String): Boolean {
        encryptedPreferences.edit().remove(key).apply()
        return true
    }

    override fun clear() {
        encryptedPreferences.edit().clear().apply()
    }

    companion object {
        /** Filename of the AES-GCM/SIV encrypted preferences store. */
        private const val ENCRYPTED_PREFS_NAME = "runanywhere_secure_storage_encrypted"

        /** Logger category for secure-storage operations. */
        private const val LOG_CATEGORY = "SecureStorage"
    }
}

/**
 * Extension function to easily set Android context for CppBridgePlatformAdapter.
 * This is the recommended way to initialize storage on Android.
 *
 * @param context The Android context (will use applicationContext internally)
 */
fun CppBridgePlatformAdapter.setContext(context: Context) {
    setPlatformStorage(AndroidKeychainManager(context))
}
