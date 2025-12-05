package com.runanywhere.runanywhereai.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Secure storage for sensitive data using EncryptedSharedPreferences
 *
 * iOS equivalent: KeychainService for secure storage
 * - KeychainService.shared.save(key: "runanywhere_api_key", data: apiKeyData)
 * - KeychainService.shared.retrieve(key: "runanywhere_api_key")
 * - KeychainService.shared.delete(key: "runanywhere_api_key")
 */
class SecureStorage(context: Context) {

    companion object {
        private const val TAG = "SecureStorage"
        private const val PREFS_NAME = "runanywhere_secure_prefs"

        // Keys matching iOS Keychain keys
        private const val KEY_API_KEY = "runanywhere_api_key"
    }

    private val masterKey: MasterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val securePrefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    /**
     * Save API key securely
     * iOS equivalent: KeychainService.shared.save(key: "runanywhere_api_key", data: apiKeyData)
     */
    fun saveApiKey(apiKey: String) {
        securePrefs.edit().putString(KEY_API_KEY, apiKey).apply()
        Log.d(TAG, "API key saved securely")
    }

    /**
     * Retrieve API key
     * iOS equivalent: KeychainService.shared.retrieve(key: "runanywhere_api_key")
     */
    fun getApiKey(): String? {
        return securePrefs.getString(KEY_API_KEY, null)
    }

    /**
     * Delete API key
     * iOS equivalent: KeychainService.shared.delete(key: "runanywhere_api_key")
     */
    fun deleteApiKey() {
        securePrefs.edit().remove(KEY_API_KEY).apply()
        Log.d(TAG, "API key deleted")
    }

    /**
     * Check if API key is configured
     * iOS equivalent: Checking if KeychainService.shared.retrieve returns non-nil
     */
    fun isApiKeyConfigured(): Boolean {
        return !getApiKey().isNullOrEmpty()
    }

    /**
     * Generic secure save for any string value
     */
    fun saveSecureString(key: String, value: String) {
        securePrefs.edit().putString(key, value).apply()
        Log.d(TAG, "Secure string saved for key: $key")
    }

    /**
     * Generic secure retrieve for any string value
     */
    fun getSecureString(key: String): String? {
        return securePrefs.getString(key, null)
    }

    /**
     * Generic secure delete for any key
     */
    fun deleteSecureString(key: String) {
        securePrefs.edit().remove(key).apply()
        Log.d(TAG, "Secure string deleted for key: $key")
    }
}
