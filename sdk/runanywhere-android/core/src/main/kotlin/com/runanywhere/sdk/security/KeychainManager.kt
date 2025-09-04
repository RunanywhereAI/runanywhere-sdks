package com.runanywhere.sdk.security

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.runanywhere.sdk.data.models.StoredTokens
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.Date

/**
 * Keychain Manager for secure token storage
 * One-to-one translation from iOS KeychainManager to Android EncryptedSharedPreferences
 * Equivalent to iOS KeychainManager.shared
 */
class KeychainManager private constructor(private val context: Context) {

    companion object {
        @Volatile
        private var INSTANCE: KeychainManager? = null

        val shared: KeychainManager
            get() = INSTANCE ?: throw IllegalStateException("KeychainManager not initialized. Call initialize(context) first.")

        fun initialize(context: Context) {
            if (INSTANCE == null) {
                synchronized(this) {
                    if (INSTANCE == null) {
                        INSTANCE = KeychainManager(context.applicationContext)
                    }
                }
            }
        }
    }

    private val logger = SDKLogger("KeychainManager")
    private val mutex = Mutex()

    private val masterKey: MasterKey by lazy {
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
    }

    private val encryptedPrefs: SharedPreferences by lazy {
        EncryptedSharedPreferences.create(
            context,
            "runanywhere_secure_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    // Keys for token storage
    private companion object {
        const val ACCESS_TOKEN_KEY = "access_token"
        const val REFRESH_TOKEN_KEY = "refresh_token"
        const val EXPIRES_AT_KEY = "expires_at"
    }

    /**
     * Save authentication tokens securely
     * Equivalent to iOS KeychainManager keychain operations
     */
    suspend fun saveTokens(accessToken: String, refreshToken: String, expiresAt: Date) = mutex.withLock {
        logger.debug("Saving tokens to keychain")

        try {
            with(encryptedPrefs.edit()) {
                putString(ACCESS_TOKEN_KEY, accessToken)
                putString(REFRESH_TOKEN_KEY, refreshToken)
                putLong(EXPIRES_AT_KEY, expiresAt.time)
                apply()
            }

            logger.debug("Tokens saved successfully")
        } catch (e: Exception) {
            logger.error("Failed to save tokens", e)
            throw e
        }
    }

    /**
     * Retrieve stored authentication tokens
     * Equivalent to iOS KeychainManager keychain queries
     */
    suspend fun getTokens(): StoredTokens? = mutex.withLock {
        logger.debug("Retrieving tokens from keychain")

        try {
            val accessToken = encryptedPrefs.getString(ACCESS_TOKEN_KEY, null)
            val refreshToken = encryptedPrefs.getString(REFRESH_TOKEN_KEY, null)
            val expiresAtMillis = encryptedPrefs.getLong(EXPIRES_AT_KEY, -1L)

            if (accessToken != null && refreshToken != null && expiresAtMillis != -1L) {
                val storedTokens = StoredTokens(
                    accessToken = accessToken,
                    refreshToken = refreshToken,
                    expiresAt = Date(expiresAtMillis)
                )

                logger.debug("Tokens retrieved successfully")
                return storedTokens
            } else {
                logger.debug("No valid tokens found")
                return null
            }
        } catch (e: Exception) {
            logger.error("Failed to retrieve tokens", e)
            return null
        }
    }

    /**
     * Delete all stored tokens
     * Equivalent to iOS KeychainManager deletion operations
     */
    suspend fun deleteTokens() = mutex.withLock {
        logger.debug("Deleting tokens from keychain")

        try {
            with(encryptedPrefs.edit()) {
                remove(ACCESS_TOKEN_KEY)
                remove(REFRESH_TOKEN_KEY)
                remove(EXPIRES_AT_KEY)
                apply()
            }

            logger.debug("Tokens deleted successfully")
        } catch (e: Exception) {
            logger.error("Failed to delete tokens", e)
            throw e
        }
    }

    /**
     * Check if tokens exist in keychain
     * Equivalent to iOS KeychainManager queries
     */
    suspend fun hasStoredTokens(): Boolean = mutex.withLock {
        try {
            val accessToken = encryptedPrefs.getString(ACCESS_TOKEN_KEY, null)
            val refreshToken = encryptedPrefs.getString(REFRESH_TOKEN_KEY, null)
            return accessToken != null && refreshToken != null
        } catch (e: Exception) {
            logger.error("Failed to check stored tokens", e)
            return false
        }
    }

    /**
     * Clear all keychain data
     * Equivalent to iOS KeychainManager clear operations
     */
    suspend fun clearAll() = mutex.withLock {
        logger.debug("Clearing all keychain data")

        try {
            with(encryptedPrefs.edit()) {
                clear()
                apply()
            }

            logger.info("All keychain data cleared")
        } catch (e: Exception) {
            logger.error("Failed to clear keychain data", e)
            throw e
        }
    }
}
