/**
 * SecureStorageManager.kt
 *
 * Android secure storage using EncryptedSharedPreferences.
 * Provides hardware-backed encryption when available (Android Keystore).
 *
 * Reference: sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/security/SecureStorage.kt
 */

package com.margelo.nitro.runanywhere

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.util.UUID

/**
 * Secure storage manager for persistent device identity and sensitive data.
 * Uses EncryptedSharedPreferences backed by Android Keystore.
 */
object SecureStorageManager {
    private const val TAG = "SecureStorageManager"
    private const val PREFS_NAME = "runanywhere_secure_prefs"
    private const val DEVICE_UUID_KEY = "com.runanywhere.sdk.device.uuid"

    @SuppressLint("StaticFieldLeak")
    private var context: Context? = null
    private var encryptedPrefs: SharedPreferences? = null

    /**
     * Get the stored context (for platform bridge operations)
     */
    @JvmStatic
    fun getContext(): Context? = context

    /**
     * Initialize with application context
     * Must be called before any other operations
     */
    @JvmStatic
    fun initialize(applicationContext: Context) {
        if (context != null) return

        context = applicationContext.applicationContext
        try {
            val masterKey = MasterKey.Builder(context!!)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            encryptedPrefs = EncryptedSharedPreferences.create(
                context!!,
                PREFS_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
            Log.i(TAG, "SecureStorageManager initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize EncryptedSharedPreferences", e)
        }
    }

    /**
     * Set a secure string value
     */
    @JvmStatic
    fun set(key: String, value: String): Boolean {
        return try {
            encryptedPrefs?.edit()?.putString(key, value)?.apply()
            Log.d(TAG, "secureSet key=$key")
            true
        } catch (e: Exception) {
            Log.e(TAG, "secureSet failed for key=$key", e)
            false
        }
    }

    /**
     * Get a secure string value
     */
    @JvmStatic
    fun get(key: String): String? {
        return try {
            val value = encryptedPrefs?.getString(key, null)
            Log.d(TAG, "secureGet key=$key found=${value != null}")
            value
        } catch (e: Exception) {
            Log.e(TAG, "secureGet failed for key=$key", e)
            null
        }
    }

    /**
     * Delete a secure value
     */
    @JvmStatic
    fun delete(key: String): Boolean {
        return try {
            encryptedPrefs?.edit()?.remove(key)?.apply()
            Log.d(TAG, "secureDelete key=$key")
            true
        } catch (e: Exception) {
            Log.e(TAG, "secureDelete failed for key=$key", e)
            false
        }
    }

    /**
     * Check if key exists
     */
    @JvmStatic
    fun exists(key: String): Boolean {
        return try {
            encryptedPrefs?.contains(key) ?: false
        } catch (e: Exception) {
            Log.e(TAG, "secureExists failed for key=$key", e)
            false
        }
    }

    /**
     * Get or create persistent device UUID
     * Survives app reinstalls (stored in EncryptedSharedPreferences)
     */
    @JvmStatic
    fun getPersistentDeviceUUID(): String {
        // Try to get existing UUID
        val existingUUID = get(DEVICE_UUID_KEY)
        if (!existingUUID.isNullOrEmpty()) {
            Log.i(TAG, "Loaded persistent device UUID from secure storage")
            return existingUUID
        }

        // Generate new UUID
        val newUUID = UUID.randomUUID().toString()
        if (set(DEVICE_UUID_KEY, newUUID)) {
            Log.i(TAG, "Generated and stored new persistent device UUID")
        } else {
            Log.w(TAG, "Generated device UUID but failed to persist")
        }
        return newUUID
    }
}

