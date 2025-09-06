package com.runanywhere.sdk.storage

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import androidx.core.content.edit

/**
 * Android implementation of SecureStorage using EncryptedSharedPreferences
 */
internal class AndroidSecureStorage(context: Context) : SecureStorage {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val sharedPreferences = EncryptedSharedPreferences.create(
        context,
        "runanywhere_secure_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    override suspend fun setSecureString(key: String, value: String) {
        sharedPreferences.edit { putString(key, value) }
    }

    override suspend fun getSecureString(key: String): String? {
        return sharedPreferences.getString(key, null)
    }

    override suspend fun removeSecure(key: String) {
        sharedPreferences.edit { remove(key) }
    }

    override suspend fun containsSecure(key: String): Boolean {
        return sharedPreferences.contains(key)
    }

    override suspend fun clearSecure() {
        sharedPreferences.edit { clear() }
    }
}

/**
 * Factory function to create secure storage for Android
 */
actual fun createSecureStorage(): SecureStorage =
    AndroidSecureStorage(AndroidPlatformContext.applicationContext)
