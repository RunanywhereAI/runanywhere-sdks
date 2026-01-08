/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform adapter extension for CppBridge.
 * Provides JNI callbacks for platform-specific operations required by C++ core.
 *
 * Follows iOS CppBridge+PlatformAdapter.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Platform adapter that provides JNI callbacks for C++ core operations.
 *
 * CRITICAL: This MUST be registered FIRST before any C++ calls.
 * CRITICAL: [setContext] MUST be called before secure storage operations on Android.
 *
 * Provides callbacks for:
 * - Logging: Route C++ logs to Kotlin logging system
 * - File Operations: fileExists, fileRead, fileWrite, fileDelete
 * - Secure Storage: secureGet, secureSet, secureDelete (encrypted key-value store)
 * - Clock: nowMs (current timestamp in milliseconds)
 */
object CppBridgePlatformAdapter {
    /**
     * Log level constants matching C++ RAC_LOG_LEVEL_* values.
     */
    object LogLevel {
        const val TRACE = 0
        const val DEBUG = 1
        const val INFO = 2
        const val WARN = 3
        const val ERROR = 4
        const val FATAL = 5
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * Application context for Android-specific operations.
     * Must be set via [setContext] before secure storage operations.
     */
    @Volatile
    private var appContext: Context? = null

    /**
     * SharedPreferences for persistent secure storage on Android.
     * Initialized when context is set.
     *
     * @Volatile ensures visibility across threads - reads will see the latest
     * value written by setContext() even without explicit synchronization.
     */
    @Volatile
    private var sharedPreferences: SharedPreferences? = null

    /**
     * SharedPreferences file name for secure storage.
     */
    private const val PREFS_NAME = "runanywhere_secure_storage"

    /**
     * In-memory fallback storage for JVM environments or when context is not available.
     */
    private val inMemoryStorage = ConcurrentHashMap<String, ByteArray>()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridge"

    /**
     * Set the Android application context.
     *
     * MUST be called during SDK initialization before any secure storage operations.
     * Uses application context to avoid memory leaks.
     *
     * @param context The Android context (will use applicationContext internally)
     */
    fun setContext(context: Context) {
        synchronized(lock) {
            appContext = context.applicationContext
            sharedPreferences = appContext?.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            logCallback(LogLevel.DEBUG, TAG, "Context set, SharedPreferences initialized for persistent storage")
        }
    }

    /**
     * Register the platform adapter with C++ core.
     *
     * This MUST be called before any other C++ operations.
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Register all callbacks with C++ via JNI
            // The actual JNI registration happens in native code using RegisterNatives()
            // or via the native library initialization

            // TODO: Call native registration
            // nativeRegisterPlatformAdapter(
            //     logCallback = ::logCallback,
            //     fileExistsCallback = ::fileExistsCallback,
            //     fileReadCallback = ::fileReadCallback,
            //     fileWriteCallback = ::fileWriteCallback,
            //     fileDeleteCallback = ::fileDeleteCallback,
            //     secureGetCallback = ::secureGetCallback,
            //     secureSetCallback = ::secureSetCallback,
            //     secureDeleteCallback = ::secureDeleteCallback,
            //     nowMsCallback = ::nowMsCallback
            // )

            isRegistered = true
        }
    }

    /**
     * Check if the platform adapter is registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // LOGGING CALLBACKS
    // ========================================================================

    /**
     * Log callback for C++ core.
     *
     * Routes C++ log messages to Kotlin logging system.
     *
     * @param level The log level (see [LogLevel] constants)
     * @param tag The log tag/category
     * @param message The log message
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun logCallback(level: Int, tag: String, message: String) {
        val formattedTag = "$TAG/$tag"

        when (level) {
            LogLevel.TRACE, LogLevel.DEBUG -> {
                // Debug level logging
                println("D/$formattedTag: $message")
            }
            LogLevel.INFO -> {
                println("I/$formattedTag: $message")
            }
            LogLevel.WARN -> {
                println("W/$formattedTag: $message")
            }
            LogLevel.ERROR, LogLevel.FATAL -> {
                System.err.println("E/$formattedTag: $message")
            }
            else -> {
                println("?/$formattedTag: $message")
            }
        }
    }

    // ========================================================================
    // FILE OPERATION CALLBACKS
    // ========================================================================

    /**
     * Check if a file exists at the given path.
     *
     * @param path The file path to check
     * @return true if the file exists, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun fileExistsCallback(path: String): Boolean {
        return try {
            File(path).exists()
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "FileOps", "fileExists failed for '$path': ${e.message}")
            false
        }
    }

    /**
     * Read file contents as bytes.
     *
     * @param path The file path to read
     * @return The file contents as ByteArray, or null if read fails
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun fileReadCallback(path: String): ByteArray? {
        return try {
            val file = File(path)
            if (!file.exists()) {
                logCallback(LogLevel.WARN, "FileOps", "fileRead: file not found '$path'")
                return null
            }
            file.readBytes()
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "FileOps", "fileRead failed for '$path': ${e.message}")
            null
        }
    }

    /**
     * Write bytes to a file.
     *
     * @param path The file path to write to
     * @param data The data to write
     * @return true if write succeeded, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun fileWriteCallback(path: String, data: ByteArray): Boolean {
        return try {
            val file = File(path)
            // Create parent directories if they don't exist
            file.parentFile?.mkdirs()
            file.writeBytes(data)
            true
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "FileOps", "fileWrite failed for '$path': ${e.message}")
            false
        }
    }

    /**
     * Delete a file at the given path.
     *
     * @param path The file path to delete
     * @return true if delete succeeded or file didn't exist, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun fileDeleteCallback(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) {
                return true // File doesn't exist, consider it deleted
            }
            file.delete()
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "FileOps", "fileDelete failed for '$path': ${e.message}")
            false
        }
    }

    // ========================================================================
    // SECURE STORAGE CALLBACKS
    // ========================================================================

    /**
     * Get a value from secure storage.
     *
     * On Android with context set: Uses SharedPreferences (persistent across app restarts)
     * On JVM or without context: Uses in-memory storage (non-persistent)
     *
     * @param key The key to retrieve
     * @return The stored value as ByteArray, or null if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun secureGetCallback(key: String): ByteArray? {
        return try {
            // Take a thread-safe local copy of the volatile reference
            val prefs = sharedPreferences

            // Try SharedPreferences first (persistent storage)
            if (prefs != null) {
                val base64Value = prefs.getString(key, null)
                if (base64Value != null) {
                    return Base64.decode(base64Value, Base64.NO_WRAP)
                }
            }
            // Fall back to in-memory storage
            inMemoryStorage[key]
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "SecureStorage", "secureGet failed for key '$key': ${e.message}")
            null
        }
    }

    /**
     * Store a value in secure storage.
     *
     * On Android with context set: Uses SharedPreferences (persistent across app restarts)
     * On JVM or without context: Uses in-memory storage (non-persistent)
     *
     * @param key The key to store under
     * @param value The value to store
     * @return true if storage succeeded, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun secureSetCallback(key: String, value: ByteArray): Boolean {
        return try {
            // Take a thread-safe local copy of the volatile reference
            val prefs = sharedPreferences

            // Try SharedPreferences first (persistent storage)
            if (prefs != null) {
                val base64Value = Base64.encodeToString(value, Base64.NO_WRAP)
                prefs.edit().putString(key, base64Value).apply()
                logCallback(LogLevel.DEBUG, "SecureStorage", "Persisted key '$key' to SharedPreferences")
                return true
            }
            // Fall back to in-memory storage
            inMemoryStorage[key] = value.copyOf()
            logCallback(LogLevel.WARN, "SecureStorage", "Using in-memory storage for key '$key' (context not set)")
            true
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "SecureStorage", "secureSet failed for key '$key': ${e.message}")
            false
        }
    }

    /**
     * Delete a value from secure storage.
     *
     * @param key The key to delete
     * @return true if delete succeeded or key didn't exist, false otherwise
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun secureDeleteCallback(key: String): Boolean {
        return try {
            // Take a thread-safe local copy of the volatile reference
            val prefs = sharedPreferences

            // Remove from SharedPreferences if available
            prefs?.edit()?.remove(key)?.apply()
            // Also remove from in-memory
            inMemoryStorage.remove(key)
            true
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "SecureStorage", "secureDelete failed for key '$key': ${e.message}")
            false
        }
    }

    // ========================================================================
    // CLOCK CALLBACKS
    // ========================================================================

    /**
     * Get the current time in milliseconds since Unix epoch.
     *
     * @return Current timestamp in milliseconds
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun nowMsCallback(): Long {
        return System.currentTimeMillis()
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to register the platform adapter with C++ core.
     *
     * This is called during [register] to pass callback references to native code.
     * Reserved for future native callback integration.
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeRegisterPlatformAdapter()

    /**
     * Native method to unregister the platform adapter.
     *
     * Called during shutdown to clean up native resources.
     * Reserved for future native callback integration.
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeUnregisterPlatformAdapter()

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the platform adapter and clean up resources.
     *
     * Called during SDK shutdown.
     * Note: Does NOT clear persistent storage (device ID should survive SDK restarts)
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnregisterPlatformAdapter()

            // Only clear in-memory storage, preserve persistent storage
            inMemoryStorage.clear()
            isRegistered = false
        }
    }

    /**
     * Clear all secure storage entries (both persistent and in-memory).
     *
     * WARNING: This clears the device ID! Device will be re-registered on next app start.
     * Useful for testing or when user requests data deletion.
     */
    fun clearSecureStorage() {
        // Clear SharedPreferences
        sharedPreferences?.edit()?.clear()?.apply()
        // Clear in-memory storage
        inMemoryStorage.clear()
        logCallback(LogLevel.INFO, "SecureStorage", "All secure storage cleared")
    }
}
