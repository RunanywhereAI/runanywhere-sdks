package com.runanywhere.sdk.storage

import android.content.Context
import android.content.SharedPreferences

/**
 * Android implementation of PlatformStorage using SharedPreferences
 */
internal class AndroidPlatformStorage(context: Context) : PlatformStorage {
    private val sharedPreferences: SharedPreferences =
        context.getSharedPreferences("runanywhere_sdk_prefs", Context.MODE_PRIVATE)

    override suspend fun putString(key: String, value: String) {
        sharedPreferences.edit().putString(key, value).apply()
    }

    override suspend fun getString(key: String): String? {
        return sharedPreferences.getString(key, null)
    }

    override suspend fun putBoolean(key: String, value: Boolean) {
        sharedPreferences.edit().putBoolean(key, value).apply()
    }

    override suspend fun getBoolean(key: String, defaultValue: Boolean): Boolean {
        return sharedPreferences.getBoolean(key, defaultValue)
    }

    override suspend fun putLong(key: String, value: Long) {
        sharedPreferences.edit().putLong(key, value).apply()
    }

    override suspend fun getLong(key: String, defaultValue: Long): Long {
        return sharedPreferences.getLong(key, defaultValue)
    }

    override suspend fun putInt(key: String, value: Int) {
        sharedPreferences.edit().putInt(key, value).apply()
    }

    override suspend fun getInt(key: String, defaultValue: Int): Int {
        return sharedPreferences.getInt(key, defaultValue)
    }

    override suspend fun remove(key: String) {
        sharedPreferences.edit().remove(key).apply()
    }

    override suspend fun clear() {
        sharedPreferences.edit().clear().apply()
    }

    override suspend fun contains(key: String): Boolean {
        return sharedPreferences.contains(key)
    }

    override suspend fun getAllKeys(): Set<String> {
        return sharedPreferences.all.keys
    }
}

/**
 * Factory function to create platform storage for Android
 */
actual fun createPlatformStorage(): PlatformStorage =
    AndroidPlatformStorage(AndroidPlatformContext.applicationContext)
