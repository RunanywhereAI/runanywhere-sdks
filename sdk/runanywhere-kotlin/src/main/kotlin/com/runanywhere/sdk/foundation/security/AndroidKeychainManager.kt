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
import com.runanywhere.sdk.generated.convenience.fromWireString
import com.runanywhere.sdk.generated.convenience.wireString
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import com.runanywhere.sdk.public.configuration.SDKInitParams

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

    /**
     * Store SDK initialization parameters securely.
     *
     * Mirrors Swift KeychainManager.storeSDKParams(_:): api key, base URL, and
     * environment wire string are persisted under stable SDK keys.
     */
    fun storeSDKParams(params: SDKInitParams): Boolean {
        val success =
            setString(KEY_API_KEY, params.apiKey) &&
                setString(KEY_BASE_URL, params.baseURL) &&
                setString(KEY_ENVIRONMENT, params.environment.wireString)
        if (success) {
            logger.info("SDK parameters stored securely")
        }
        return success
    }

    /**
     * Retrieve stored SDK initialization parameters, validating them before
     * returning. Returns null when any field is absent or invalid.
     */
    fun retrieveSDKParams(): SDKInitParams? {
        val apiKey = getString(KEY_API_KEY) ?: return null
        val baseURL = getString(KEY_BASE_URL) ?: return null
        val environment =
            getString(KEY_ENVIRONMENT)
                ?.let { SDKEnvironment.fromWireString(it) }
                ?: return null

        return runCatching {
            SDKInitParams.create(apiKey = apiKey, baseURL = baseURL, environment = environment)
        }.onSuccess {
            logger.debug("Retrieved SDK parameters from secure storage")
        }.onFailure {
            logger.debug("Stored SDK parameters were invalid: ${it.message}")
        }.getOrNull()
    }

    /** Clear stored SDK initialization parameters. */
    fun clearSDKParams(): Boolean =
        delete(KEY_API_KEY) &&
            delete(KEY_BASE_URL) &&
            delete(KEY_ENVIRONMENT)

    private fun setString(key: String, value: String): Boolean =
        set(key, value.toByteArray(Charsets.UTF_8))

    private fun getString(key: String): String? =
        get(key)?.toString(Charsets.UTF_8)

    companion object {
        /** Filename of the AES-GCM/SIV encrypted preferences store. */
        private const val ENCRYPTED_PREFS_NAME = "runanywhere_secure_storage_encrypted"

        /** Logger category for secure-storage operations. */
        private const val LOG_CATEGORY = "SecureStorage"

        private const val KEY_API_KEY = "com.runanywhere.sdk.apiKey"
        private const val KEY_BASE_URL = "com.runanywhere.sdk.baseURL"
        private const val KEY_ENVIRONMENT = "com.runanywhere.sdk.environment"
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
