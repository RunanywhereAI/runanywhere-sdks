package com.runanywhere.sdk.storage

/**
 * Platform-specific storage abstraction for key-value persistence
 * This will be implemented differently on each platform (SharedPreferences, UserDefaults, etc.)
 */
interface PlatformStorage {
    /**
     * Save a string value
     */
    suspend fun putString(
        key: String,
        value: String,
    )

    /**
     * Get a string value
     */
    suspend fun getString(key: String): String?

    /**
     * Save a boolean value
     */
    suspend fun putBoolean(
        key: String,
        value: Boolean,
    )

    /**
     * Get a boolean value
     */
    suspend fun getBoolean(
        key: String,
        defaultValue: Boolean = false,
    ): Boolean

    /**
     * Save a long value
     */
    suspend fun putLong(
        key: String,
        value: Long,
    )

    /**
     * Get a long value
     */
    suspend fun getLong(
        key: String,
        defaultValue: Long = 0L,
    ): Long

    /**
     * Save an integer value
     */
    suspend fun putInt(
        key: String,
        value: Int,
    )

    /**
     * Get an integer value
     */
    suspend fun getInt(
        key: String,
        defaultValue: Int = 0,
    ): Int

    /**
     * Remove a value
     */
    suspend fun remove(key: String)

    /**
     * Clear all stored values
     */
    suspend fun clear()

    /**
     * Check if a key exists
     */
    suspend fun contains(key: String): Boolean

    /**
     * Get all keys
     */
    suspend fun getAllKeys(): Set<String>
}

/**
 * Expected to be provided by each platform
 */
expect fun createPlatformStorage(): PlatformStorage
