package com.runanywhere.sdk.storage

import com.runanywhere.sdk.foundation.SDKLogger
import java.util.Base64
import java.util.prefs.Preferences
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec

/**
 * JVM implementation of secure credential storage
 * Uses Java Preferences API with optional encryption
 */
object KeychainManager {
    private val logger = SDKLogger("KeychainManager")
    private val prefs: Preferences = Preferences.userNodeForPackage(KeychainManager::class.java)
    private const val API_KEY_PREF = "runanywhere_api_key"
    private const val ENCRYPTION_KEY_PREF = "runanywhere_encryption_key"

    /**
     * Store API key securely
     */
    fun storeAPIKey(apiKey: String) {
        try {
            // For production, encrypt the API key
            val encryptedKey = encrypt(apiKey)
            prefs.put(API_KEY_PREF, encryptedKey)
            prefs.flush()
            logger.debug("API key stored securely")
        } catch (e: Exception) {
            logger.error("Failed to store API key securely", e)
            // Fallback to plain storage
            prefs.put(API_KEY_PREF, apiKey)
            prefs.flush()
        }
    }

    /**
     * Retrieve API key
     */
    fun getAPIKey(): String? =
        try {
            val stored = prefs.get(API_KEY_PREF, null)
            if (stored != null) {
                decrypt(stored)
            } else {
                null
            }
        } catch (e: Exception) {
            logger.error("Failed to retrieve API key", e)
            // Try as plain text
            prefs.get(API_KEY_PREF, null)
        }

    /**
     * Clear stored credentials
     */
    fun clear() {
        prefs.remove(API_KEY_PREF)
        prefs.remove(ENCRYPTION_KEY_PREF)
        prefs.flush()
        logger.debug("Cleared stored credentials")
    }

    /**
     * Simple encryption for API key
     */
    private fun encrypt(plainText: String): String {
        val key = getOrCreateEncryptionKey()
        val cipher = Cipher.getInstance("AES")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val encrypted = cipher.doFinal(plainText.toByteArray())
        return Base64.getEncoder().encodeToString(encrypted)
    }

    /**
     * Decrypt API key
     */
    private fun decrypt(encryptedText: String): String {
        val key = getOrCreateEncryptionKey()
        val cipher = Cipher.getInstance("AES")
        cipher.init(Cipher.DECRYPT_MODE, key)
        val decrypted = cipher.doFinal(Base64.getDecoder().decode(encryptedText))
        return String(decrypted)
    }

    /**
     * Get or create encryption key
     */
    private fun getOrCreateEncryptionKey(): SecretKey {
        val storedKey = prefs.get(ENCRYPTION_KEY_PREF, null)
        return if (storedKey != null) {
            // Restore existing key
            val decodedKey = Base64.getDecoder().decode(storedKey)
            SecretKeySpec(decodedKey, 0, decodedKey.size, "AES")
        } else {
            // Generate new key
            val keyGen = KeyGenerator.getInstance("AES")
            keyGen.init(128) // 128-bit AES
            val secretKey = keyGen.generateKey()

            // Store for future use
            val encodedKey = Base64.getEncoder().encodeToString(secretKey.encoded)
            prefs.put(ENCRYPTION_KEY_PREF, encodedKey)
            prefs.flush()

            secretKey
        }
    }
}
