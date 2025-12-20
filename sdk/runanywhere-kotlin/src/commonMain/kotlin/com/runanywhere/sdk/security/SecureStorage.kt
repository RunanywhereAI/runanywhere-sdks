package com.runanywhere.sdk.security

import com.runanywhere.sdk.data.models.SDKError

/**
 * Platform-agnostic secure storage interface
 * Matches iOS KeychainManager functionality for credential storage
 * Platform implementations should use:
 * - Android: EncryptedSharedPreferences with AndroidKeystore
 * - JVM: Encrypted file storage or system keystore
 * - Native: Platform-specific secure storage APIs
 */
interface SecureStorage {
    /**
     * Store a string value securely
     * @param key Unique identifier for the value
     * @param value String value to store
     * @throws SDKError.SecurityError if storage fails
     */
    suspend fun setSecureString(
        key: String,
        value: String,
    )

    /**
     * Retrieve a stored string value
     * @param key Unique identifier for the value
     * @return Stored string value or null if not found
     * @throws SDKError.SecurityError if retrieval fails
     */
    suspend fun getSecureString(key: String): String?

    /**
     * Store binary data securely
     * @param key Unique identifier for the data
     * @param data Binary data to store
     * @throws SDKError.SecurityError if storage fails
     */
    suspend fun setSecureData(
        key: String,
        data: ByteArray,
    )

    /**
     * Retrieve stored binary data
     * @param key Unique identifier for the data
     * @return Stored binary data or null if not found
     * @throws SDKError.SecurityError if retrieval fails
     */
    suspend fun getSecureData(key: String): ByteArray?

    /**
     * Remove a stored value
     * @param key Unique identifier for the value to remove
     * @throws SDKError.SecurityError if removal fails
     */
    suspend fun removeSecure(key: String)

    /**
     * Check if a key exists in secure storage
     * @param key Unique identifier to check
     * @return true if key exists, false otherwise
     */
    suspend fun containsKey(key: String): Boolean

    /**
     * Clear all stored values (use with caution)
     * @throws SDKError.SecurityError if clear operation fails
     */
    suspend fun clearAll()

    /**
     * Get all stored keys (for debugging/migration purposes)
     * @return Set of all stored keys
     */
    suspend fun getAllKeys(): Set<String>

    /**
     * Check if secure storage is available and properly configured
     * @return true if secure storage is available, false otherwise
     */
    suspend fun isAvailable(): Boolean
}

/**
 * Platform-specific secure storage factory
 * Each platform provides its own implementation
 */
@Suppress("UtilityClassWithPublicConstructor") // KMP expect/actual pattern requires class
expect class SecureStorageFactory {
    companion object {
        /**
         * Create a platform-specific secure storage instance
         * @param identifier Unique identifier for this storage instance (optional)
         * @return Platform-appropriate SecureStorage implementation
         */
        fun create(identifier: String = "com.runanywhere.sdk"): SecureStorage

        /**
         * Check if secure storage is supported on this platform
         * @return true if supported, false otherwise
         */
        fun isSupported(): Boolean
    }
}

/**
 * Convenience functions for common secure storage operations
 */
object SecureStorageUtils {
    /**
     * Store authentication tokens securely
     */
    suspend fun storeAuthTokens(
        storage: SecureStorage,
        accessToken: String,
        refreshToken: String?,
        expiresAt: Long,
    ) {
        storage.setSecureString("access_token", accessToken)
        refreshToken?.let { storage.setSecureString("refresh_token", it) }
        storage.setSecureString("token_expires_at", expiresAt.toString())
    }

    /**
     * Retrieve authentication tokens from secure storage
     */
    suspend fun getAuthTokens(storage: SecureStorage): AuthTokens? {
        val accessToken = storage.getSecureString("access_token") ?: return null
        val refreshToken = storage.getSecureString("refresh_token")
        val expiresAt = storage.getSecureString("token_expires_at")?.toLongOrNull() ?: 0L

        return AuthTokens(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresAt = expiresAt,
        )
    }

    /**
     * Clear all authentication data
     */
    suspend fun clearAuthTokens(storage: SecureStorage) {
        storage.removeSecure("access_token")
        storage.removeSecure("refresh_token")
        storage.removeSecure("token_expires_at")
        storage.removeSecure("device_id")
        storage.removeSecure("organization_id")
        storage.removeSecure("user_id")
    }
}

/**
 * Data class for authentication tokens
 */
data class AuthTokens(
    val accessToken: String,
    val refreshToken: String? = null,
    val expiresAt: Long,
)
