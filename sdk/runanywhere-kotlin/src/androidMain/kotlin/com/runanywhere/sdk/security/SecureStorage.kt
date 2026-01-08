package com.runanywhere.sdk.security

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Android implementation of SecureStorage using EncryptedSharedPreferences
 * Provides hardware-backed encryption when available (Android Keystore)
 */
class AndroidSecureStorage private constructor(
    private val encryptedPrefs: SharedPreferences,
    private val identifier: String,
) : SecureStorage {
    private val logger = SDKLogger("AndroidSecureStorage")

    companion object {
        // Suppress: Using applicationContext which is safe (doesn't leak Activity)
        @SuppressLint("StaticFieldLeak")
        private var cachedStorage: AndroidSecureStorage? = null

        @SuppressLint("StaticFieldLeak")
        private var context: Context? = null

        /**
         * Initialize Android secure storage with application context
         * This should be called during SDK initialization
         */
        fun initialize(applicationContext: Context) {
            context = applicationContext.applicationContext
        }

        /**
         * Create secure storage instance for Android
         */
        fun create(identifier: String): AndroidSecureStorage {
            val appContext =
                context
                    ?: throw SDKError.storage("AndroidSecureStorage not initialized. Call initialize(context) first.")

            // Return cached instance if available for the same identifier
            cachedStorage?.let { cached ->
                if (cached.identifier == identifier) {
                    return cached
                }
            }

            try {
                // Create or retrieve master key for encryption
                val masterKey =
                    MasterKey
                        .Builder(appContext)
                        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                        .build()

                // Create encrypted shared preferences
                val encryptedPrefs =
                    EncryptedSharedPreferences.create(
                        appContext,
                        "$identifier.secure_prefs",
                        masterKey,
                        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                    )

                val storage = AndroidSecureStorage(encryptedPrefs, identifier)
                cachedStorage = storage
                return storage
            } catch (e: Exception) {
                throw SDKError.storage("Failed to create secure storage: ${e.message}")
            }
        }

        /**
         * Check if secure storage is supported on Android
         */
        fun isSupported(): Boolean =
            try {
                context != null
            } catch (e: Exception) {
                false
            }
    }

    override suspend fun setSecureString(
        key: String,
        value: String,
    ) = withContext(Dispatchers.IO) {
        try {
            encryptedPrefs
                .edit()
                .putString(key, value)
                .apply()
            logger.debug("Stored secure string for key: $key")
        } catch (e: Exception) {
            logger.error("Failed to store secure string for key: $key", e)
            throw SDKError.storage("Failed to store secure data: ${e.message}")
        }
    }

    override suspend fun getSecureString(key: String): String? =
        withContext(Dispatchers.IO) {
            try {
                val value = encryptedPrefs.getString(key, null)
                if (value != null) {
                    logger.debug("Retrieved secure string for key: $key")
                }
                value
            } catch (e: Exception) {
                logger.error("Failed to retrieve secure string for key: $key", e)
                throw SDKError.storage("Failed to retrieve secure data: ${e.message}")
            }
        }

    override suspend fun setSecureData(
        key: String,
        data: ByteArray,
    ) = withContext(Dispatchers.IO) {
        try {
            // Convert binary data to Base64 for storage in SharedPreferences
            val base64Data = android.util.Base64.encodeToString(data, android.util.Base64.DEFAULT)
            encryptedPrefs
                .edit()
                .putString("${key}_data", base64Data)
                .apply()
            logger.debug("Stored secure data for key: $key (${data.size} bytes)")
        } catch (e: Exception) {
            logger.error("Failed to store secure data for key: $key", e)
            throw SDKError.storage("Failed to store secure data: ${e.message}")
        }
    }

    override suspend fun getSecureData(key: String): ByteArray? =
        withContext(Dispatchers.IO) {
            try {
                val base64Data = encryptedPrefs.getString("${key}_data", null)
                if (base64Data != null) {
                    val data = android.util.Base64.decode(base64Data, android.util.Base64.DEFAULT)
                    logger.debug("Retrieved secure data for key: $key (${data.size} bytes)")
                    data
                } else {
                    null
                }
            } catch (e: Exception) {
                logger.error("Failed to retrieve secure data for key: $key", e)
                throw SDKError.storage("Failed to retrieve secure data: ${e.message}")
            }
        }

    override suspend fun removeSecure(key: String) =
        withContext(Dispatchers.IO) {
            try {
                encryptedPrefs
                    .edit()
                    .remove(key)
                    .remove("${key}_data") // Also remove binary data variant
                    .apply()
                logger.debug("Removed secure data for key: $key")
            } catch (e: Exception) {
                logger.error("Failed to remove secure data for key: $key", e)
                throw SDKError.storage("Failed to remove secure data: ${e.message}")
            }
        }

    override suspend fun containsKey(key: String): Boolean =
        withContext(Dispatchers.IO) {
            try {
                encryptedPrefs.contains(key) || encryptedPrefs.contains("${key}_data")
            } catch (e: Exception) {
                logger.error("Failed to check key existence: $key", e)
                false
            }
        }

    override suspend fun clearAll() =
        withContext(Dispatchers.IO) {
            try {
                encryptedPrefs.edit().clear().apply()
                logger.info("Cleared all secure data")
            } catch (e: Exception) {
                logger.error("Failed to clear all secure data", e)
                throw SDKError.storage("Failed to clear secure data: ${e.message}")
            }
        }

    override suspend fun getAllKeys(): Set<String> =
        withContext(Dispatchers.IO) {
            try {
                // Filter out the "_data" suffix keys to avoid duplicates
                encryptedPrefs.all.keys
                    .filter { !it.endsWith("_data") }
                    .toSet()
            } catch (e: Exception) {
                logger.error("Failed to get all keys", e)
                emptySet()
            }
        }

    override suspend fun isAvailable(): Boolean =
        withContext(Dispatchers.IO) {
            try {
                // Test by trying to read/write a test value
                val testKey = "availability_test"
                val testValue = "test"

                encryptedPrefs.edit().putString(testKey, testValue).apply()
                val retrievedValue = encryptedPrefs.getString(testKey, null)
                encryptedPrefs.edit().remove(testKey).apply()

                retrievedValue == testValue
            } catch (e: Exception) {
                logger.error("Secure storage availability test failed", e)
                false
            }
        }
}

/**
 * Android implementation of SecureStorageFactory
 */
@Suppress("UtilityClassWithPublicConstructor") // KMP expect/actual pattern requires class
actual class SecureStorageFactory {
    actual companion object {
        actual fun create(identifier: String): SecureStorage = AndroidSecureStorage.create(identifier)

        actual fun isSupported(): Boolean = AndroidSecureStorage.isSupported()
    }
}
