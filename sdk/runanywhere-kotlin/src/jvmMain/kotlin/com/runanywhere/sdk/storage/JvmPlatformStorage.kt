package com.runanywhere.sdk.storage

import java.util.concurrent.ConcurrentHashMap

/**
 * JVM implementation of PlatformStorage using in-memory storage
 * For production, this could be replaced with file-based storage using Properties
 */
internal class JvmPlatformStorage : PlatformStorage {
    private val storage = ConcurrentHashMap<String, String>()

    override suspend fun putString(
        key: String,
        value: String,
    ) {
        storage[key] = value
    }

    override suspend fun getString(key: String): String? = storage[key]

    override suspend fun putBoolean(
        key: String,
        value: Boolean,
    ) {
        storage[key] = value.toString()
    }

    override suspend fun getBoolean(
        key: String,
        defaultValue: Boolean,
    ): Boolean = storage[key]?.toBoolean() ?: defaultValue

    override suspend fun putLong(
        key: String,
        value: Long,
    ) {
        storage[key] = value.toString()
    }

    override suspend fun getLong(
        key: String,
        defaultValue: Long,
    ): Long = storage[key]?.toLongOrNull() ?: defaultValue

    override suspend fun putInt(
        key: String,
        value: Int,
    ) {
        storage[key] = value.toString()
    }

    override suspend fun getInt(
        key: String,
        defaultValue: Int,
    ): Int = storage[key]?.toIntOrNull() ?: defaultValue

    override suspend fun remove(key: String) {
        storage.remove(key)
    }

    override suspend fun clear() {
        storage.clear()
    }

    override suspend fun contains(key: String): Boolean = storage.containsKey(key)

    override suspend fun getAllKeys(): Set<String> = storage.keys.toSet()
}

/**
 * Factory function to create platform storage for JVM
 */
actual fun createPlatformStorage(): PlatformStorage = JvmPlatformStorage()
