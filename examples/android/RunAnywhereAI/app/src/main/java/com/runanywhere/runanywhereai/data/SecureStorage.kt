package com.runanywhere.runanywhereai.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.runanywhere.runanywhereai.BuildConfig

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

    // Fallback to regular SharedPreferences if encryption fails
    private var isEncryptionAvailable = true

    private val masterKey: MasterKey? =
        try {
            MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create MasterKey, falling back to unencrypted storage: ${e.message}")
            isEncryptionAvailable = false
            null
        }

    private val securePrefs: SharedPreferences =
        try {
            if (masterKey != null) {
                EncryptedSharedPreferences.create(
                    context,
                    PREFS_NAME,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                )
            } else {
                // Fallback to regular SharedPreferences
                context.getSharedPreferences(PREFS_NAME + "_fallback", Context.MODE_PRIVATE)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create EncryptedSharedPreferences, falling back: ${e.message}")
            isEncryptionAvailable = false
            context.getSharedPreferences(PREFS_NAME + "_fallback", Context.MODE_PRIVATE)
        }

    /**
     * Check if encrypted storage is being used
     */
    fun isUsingEncryptedStorage(): Boolean = isEncryptionAvailable

    /**
     * Save API key securely
     * iOS equivalent: KeychainService.shared.save(key: "runanywhere_api_key", data: apiKeyData)
     */
    fun saveApiKey(apiKey: String) {
        securePrefs.edit().putString(KEY_API_KEY, apiKey).apply()
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "API key saved${if (isEncryptionAvailable) " securely" else " (fallback storage)"}")
        }
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
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "API key deleted")
        }
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
    fun saveSecureString(
        key: String,
        value: String,
    ) {
        securePrefs.edit().putString(key, value).apply()
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "Secure string saved")
        }
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
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "Secure string deleted")
        }
    }
}
