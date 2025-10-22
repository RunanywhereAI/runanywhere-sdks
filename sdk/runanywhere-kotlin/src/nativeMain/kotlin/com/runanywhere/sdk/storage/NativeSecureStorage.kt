package com.runanywhere.sdk.storage

/**
 * Native implementation of SecureStorage using in-memory storage
 * This is a basic implementation - in production use platform-specific secure storage
 */
internal class NativeSecureStorage : SecureStorage {
    private val storage = mutableMapOf<String, String>()

    override suspend fun setSecureString(key: String, value: String) {
        storage[key] = value
    }

    override suspend fun getSecureString(key: String): String? {
        return storage[key]
    }

    override suspend fun removeSecure(key: String) {
        storage.remove(key)
    }

    override suspend fun containsSecure(key: String): Boolean {
        return storage.containsKey(key)
    }

    override suspend fun clearSecure() {
        storage.clear()
    }
}

/**
 * Factory function to create secure storage for native platforms
 */
actual fun createSecureStorage(): SecureStorage = NativeSecureStorage()
