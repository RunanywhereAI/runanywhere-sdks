package com.runanywhere.sdk.storage

/**
 * Platform-agnostic secure storage abstraction for sensitive data
 * Each platform implements this with appropriate security measures
 * (Keychain on iOS/macOS, EncryptedSharedPreferences on Android, etc.)
 */
interface SecureStorage {
    /**
     * Store a secure string value
     */
    suspend fun setSecureString(key: String, value: String)

    /**
     * Retrieve a secure string value
     */
    suspend fun getSecureString(key: String): String?

    /**
     * Remove a secure value
     */
    suspend fun removeSecure(key: String)

    /**
     * Check if a secure key exists
     */
    suspend fun containsSecure(key: String): Boolean

    /**
     * Clear all secure storage
     */
    suspend fun clearSecure()
}

/**
 * Expected to be provided by each platform
 */
expect fun createSecureStorage(): SecureStorage
