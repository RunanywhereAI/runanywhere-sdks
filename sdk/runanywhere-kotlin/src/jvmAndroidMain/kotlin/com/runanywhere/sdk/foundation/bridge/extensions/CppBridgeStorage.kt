/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Storage extension for CppBridge.
 * Provides storage utilities and data persistence callbacks for C++ core.
 *
 * Follows iOS CppBridge+Storage.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Storage bridge that provides storage utilities for C++ core operations.
 *
 * The C++ core needs storage functionality for:
 * - Persisting SDK configuration and state
 * - Managing cached data (model metadata, inference results)
 * - Storing user preferences and settings
 * - Temporary file management
 * - Storage quota management and cleanup
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgePlatformAdapter] and [CppBridgeModelPaths] are registered
 *
 * Thread Safety:
 * - Registration is thread-safe via synchronized block
 * - All callbacks are thread-safe
 */
object CppBridgeStorage {

    /**
     * Storage type constants matching C++ RAC_STORAGE_TYPE_* values.
     */
    object StorageType {
        /** In-memory storage (non-persistent) */
        const val MEMORY = 0

        /** Disk-based storage (persistent) */
        const val DISK = 1

        /** Cache storage (may be cleared by system) */
        const val CACHE = 2

        /** Secure storage (encrypted, persistent) */
        const val SECURE = 3

        /** Temporary storage (cleared on app restart) */
        const val TEMPORARY = 4

        /**
         * Get a human-readable name for the storage type.
         */
        fun getName(type: Int): String = when (type) {
            MEMORY -> "MEMORY"
            DISK -> "DISK"
            CACHE -> "CACHE"
            SECURE -> "SECURE"
            TEMPORARY -> "TEMPORARY"
            else -> "UNKNOWN($type)"
        }
    }

    /**
     * Storage namespace constants for organizing stored data.
     */
    object StorageNamespace {
        /** SDK configuration data */
        const val CONFIG = "config"

        /** Model metadata and registry */
        const val MODELS = "models"

        /** Inference result cache */
        const val INFERENCE_CACHE = "inference_cache"

        /** User preferences */
        const val PREFERENCES = "preferences"

        /** Session data (temporary) */
        const val SESSION = "session"

        /** Analytics and telemetry data */
        const val ANALYTICS = "analytics"

        /** Download progress and state */
        const val DOWNLOADS = "downloads"
    }

    /**
     * Storage error codes.
     */
    object StorageError {
        /** No error */
        const val NONE = 0

        /** Storage not initialized */
        const val NOT_INITIALIZED = 1

        /** Key not found */
        const val KEY_NOT_FOUND = 2

        /** Write failed */
        const val WRITE_FAILED = 3

        /** Read failed */
        const val READ_FAILED = 4

        /** Delete failed */
        const val DELETE_FAILED = 5

        /** Storage full */
        const val STORAGE_FULL = 6

        /** Invalid namespace */
        const val INVALID_NAMESPACE = 7

        /** Permission denied */
        const val PERMISSION_DENIED = 8

        /** Serialization error */
        const val SERIALIZATION_ERROR = 9

        /** Unknown error */
        const val UNKNOWN = 99

        /**
         * Get a human-readable name for the error code.
         */
        fun getName(error: Int): String = when (error) {
            NONE -> "NONE"
            NOT_INITIALIZED -> "NOT_INITIALIZED"
            KEY_NOT_FOUND -> "KEY_NOT_FOUND"
            WRITE_FAILED -> "WRITE_FAILED"
            READ_FAILED -> "READ_FAILED"
            DELETE_FAILED -> "DELETE_FAILED"
            STORAGE_FULL -> "STORAGE_FULL"
            INVALID_NAMESPACE -> "INVALID_NAMESPACE"
            PERMISSION_DENIED -> "PERMISSION_DENIED"
            SERIALIZATION_ERROR -> "SERIALIZATION_ERROR"
            UNKNOWN -> "UNKNOWN"
            else -> "UNKNOWN($error)"
        }
    }

    @Volatile
    private var isRegistered: Boolean = false

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeStorage"

    /**
     * Default storage quota in bytes (100 MB).
     */
    private const val DEFAULT_QUOTA_BYTES = 100L * 1024 * 1024

    /**
     * Default cache expiry in milliseconds (7 days).
     */
    private const val DEFAULT_CACHE_EXPIRY_MS = 7L * 24 * 60 * 60 * 1000

    /**
     * In-memory storage for MEMORY type.
     */
    private val memoryStorage = ConcurrentHashMap<String, ByteArray>()

    /**
     * Storage quota per namespace (in bytes).
     */
    private val namespaceQuotas = ConcurrentHashMap<String, Long>()

    /**
     * Storage usage per namespace (in bytes).
     */
    private val namespaceUsage = ConcurrentHashMap<String, Long>()

    /**
     * Optional listener for storage events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var storageListener: StorageListener? = null

    /**
     * Optional provider for platform-specific storage.
     * Set this on Android to provide proper app-specific storage.
     */
    @Volatile
    var storageProvider: StorageProvider? = null

    /**
     * Listener interface for storage events.
     */
    interface StorageListener {
        /**
         * Called when data is stored.
         *
         * @param namespace The storage namespace
         * @param key The key
         * @param size Size in bytes
         */
        fun onDataStored(namespace: String, key: String, size: Long)

        /**
         * Called when data is deleted.
         *
         * @param namespace The storage namespace
         * @param key The key
         */
        fun onDataDeleted(namespace: String, key: String)

        /**
         * Called when storage is cleared.
         *
         * @param namespace The storage namespace
         */
        fun onStorageCleared(namespace: String)

        /**
         * Called when storage quota is exceeded.
         *
         * @param namespace The storage namespace
         * @param usedBytes Current usage in bytes
         * @param quotaBytes Quota limit in bytes
         */
        fun onQuotaExceeded(namespace: String, usedBytes: Long, quotaBytes: Long)
    }

    /**
     * Provider interface for platform-specific storage operations.
     */
    interface StorageProvider {
        /**
         * Get the storage directory for a namespace.
         *
         * @param namespace The storage namespace
         * @param storageType The storage type
         * @return The directory path
         */
        fun getStorageDirectory(namespace: String, storageType: Int): String

        /**
         * Check if storage is available.
         *
         * @return true if storage is available
         */
        fun isStorageAvailable(): Boolean

        /**
         * Get available storage space in bytes.
         *
         * @return Available bytes
         */
        fun getAvailableSpace(): Long
    }

    /**
     * Register the storage callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // Initialize default quotas
            initializeDefaultQuotas()

            // Register the storage callbacks with C++ via JNI
            // TODO: Call native registration
            // nativeSetStorageCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Storage callbacks registered"
            )
        }
    }

    /**
     * Check if the storage callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // ========================================================================
    // STORAGE CALLBACKS
    // ========================================================================

    /**
     * Store data callback.
     *
     * Stores data in the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to store under
     * @param data The data to store
     * @param storageType The storage type (see [StorageType])
     * @return 0 on success, error code on failure
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun storeDataCallback(namespace: String, key: String, data: ByteArray, storageType: Int): Int {
        return try {
            val fullKey = "$namespace:$key"

            // Check quota
            val currentUsage = namespaceUsage.getOrDefault(namespace, 0L)
            val quota = namespaceQuotas.getOrDefault(namespace, DEFAULT_QUOTA_BYTES)

            if (currentUsage + data.size > quota) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Storage quota exceeded for namespace '$namespace'"
                )

                try {
                    storageListener?.onQuotaExceeded(namespace, currentUsage, quota)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return StorageError.STORAGE_FULL
            }

            when (storageType) {
                StorageType.MEMORY -> {
                    memoryStorage[fullKey] = data.copyOf()
                }
                StorageType.DISK, StorageType.CACHE, StorageType.TEMPORARY -> {
                    val file = getStorageFile(namespace, key, storageType)
                    file.parentFile?.mkdirs()
                    file.writeBytes(data)
                }
                StorageType.SECURE -> {
                    // Use platform adapter's secure storage
                    CppBridgePlatformAdapter.secureSetCallback(fullKey, data)
                }
                else -> {
                    return StorageError.INVALID_NAMESPACE
                }
            }

            // Update usage
            namespaceUsage[namespace] = currentUsage + data.size

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Data stored: $namespace/$key (${data.size} bytes)"
            )

            // Notify listener
            try {
                storageListener?.onDataStored(namespace, key, data.size.toLong())
            } catch (e: Exception) {
                // Ignore listener errors
            }

            StorageError.NONE
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to store data: ${e.message}"
            )
            StorageError.WRITE_FAILED
        }
    }

    /**
     * Retrieve data callback.
     *
     * Retrieves data from the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to retrieve
     * @param storageType The storage type (see [StorageType])
     * @return The stored data, or null if not found
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun retrieveDataCallback(namespace: String, key: String, storageType: Int): ByteArray? {
        return try {
            val fullKey = "$namespace:$key"

            when (storageType) {
                StorageType.MEMORY -> {
                    memoryStorage[fullKey]
                }
                StorageType.DISK, StorageType.CACHE, StorageType.TEMPORARY -> {
                    val file = getStorageFile(namespace, key, storageType)
                    if (file.exists()) file.readBytes() else null
                }
                StorageType.SECURE -> {
                    CppBridgePlatformAdapter.secureGetCallback(fullKey)
                }
                else -> null
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to retrieve data: ${e.message}"
            )
            null
        }
    }

    /**
     * Delete data callback.
     *
     * Deletes data from the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to delete
     * @param storageType The storage type (see [StorageType])
     * @return 0 on success, error code on failure
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun deleteDataCallback(namespace: String, key: String, storageType: Int): Int {
        return try {
            val fullKey = "$namespace:$key"

            when (storageType) {
                StorageType.MEMORY -> {
                    memoryStorage.remove(fullKey)
                }
                StorageType.DISK, StorageType.CACHE, StorageType.TEMPORARY -> {
                    val file = getStorageFile(namespace, key, storageType)
                    if (file.exists()) {
                        val size = file.length()
                        if (file.delete()) {
                            // Update usage
                            val currentUsage = namespaceUsage.getOrDefault(namespace, 0L)
                            namespaceUsage[namespace] = maxOf(0L, currentUsage - size)
                        }
                    }
                }
                StorageType.SECURE -> {
                    CppBridgePlatformAdapter.secureDeleteCallback(fullKey)
                }
                else -> {
                    return StorageError.INVALID_NAMESPACE
                }
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Data deleted: $namespace/$key"
            )

            // Notify listener
            try {
                storageListener?.onDataDeleted(namespace, key)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            StorageError.NONE
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to delete data: ${e.message}"
            )
            StorageError.DELETE_FAILED
        }
    }

    /**
     * Check if data exists callback.
     *
     * @param namespace The storage namespace
     * @param key The key to check
     * @param storageType The storage type (see [StorageType])
     * @return true if data exists
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun hasDataCallback(namespace: String, key: String, storageType: Int): Boolean {
        return try {
            val fullKey = "$namespace:$key"

            when (storageType) {
                StorageType.MEMORY -> {
                    memoryStorage.containsKey(fullKey)
                }
                StorageType.DISK, StorageType.CACHE, StorageType.TEMPORARY -> {
                    getStorageFile(namespace, key, storageType).exists()
                }
                StorageType.SECURE -> {
                    CppBridgePlatformAdapter.secureGetCallback(fullKey) != null
                }
                else -> false
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * List keys callback.
     *
     * Lists all keys in a namespace.
     *
     * @param namespace The storage namespace
     * @param storageType The storage type (see [StorageType])
     * @return JSON-encoded array of keys
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun listKeysCallback(namespace: String, storageType: Int): String {
        return try {
            val keys = when (storageType) {
                StorageType.MEMORY -> {
                    val prefix = "$namespace:"
                    memoryStorage.keys
                        .filter { it.startsWith(prefix) }
                        .map { it.removePrefix(prefix) }
                }
                StorageType.DISK, StorageType.CACHE, StorageType.TEMPORARY -> {
                    val dir = getStorageDirectory(namespace, storageType)
                    dir.listFiles()?.map { it.name } ?: emptyList()
                }
                else -> emptyList()
            }

            buildString {
                append("[")
                keys.forEachIndexed { index, key ->
                    if (index > 0) append(",")
                    append("\"${escapeJson(key)}\"")
                }
                append("]")
            }
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to list keys: ${e.message}"
            )
            "[]"
        }
    }

    /**
     * Clear namespace callback.
     *
     * Clears all data in a namespace.
     *
     * @param namespace The storage namespace
     * @param storageType The storage type (see [StorageType])
     * @return 0 on success, error code on failure
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun clearNamespaceCallback(namespace: String, storageType: Int): Int {
        return try {
            when (storageType) {
                StorageType.MEMORY -> {
                    val prefix = "$namespace:"
                    memoryStorage.keys
                        .filter { it.startsWith(prefix) }
                        .forEach { memoryStorage.remove(it) }
                }
                StorageType.DISK, StorageType.CACHE, StorageType.TEMPORARY -> {
                    val dir = getStorageDirectory(namespace, storageType)
                    dir.deleteRecursively()
                    dir.mkdirs()
                }
                else -> {
                    return StorageError.INVALID_NAMESPACE
                }
            }

            // Reset usage
            namespaceUsage[namespace] = 0L

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Namespace cleared: $namespace"
            )

            // Notify listener
            try {
                storageListener?.onStorageCleared(namespace)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            StorageError.NONE
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to clear namespace: ${e.message}"
            )
            StorageError.DELETE_FAILED
        }
    }

    /**
     * Get storage usage callback.
     *
     * Returns storage usage for a namespace.
     *
     * @param namespace The storage namespace
     * @return Usage in bytes
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getStorageUsageCallback(namespace: String): Long {
        return namespaceUsage.getOrDefault(namespace, 0L)
    }

    /**
     * Get storage quota callback.
     *
     * Returns storage quota for a namespace.
     *
     * @param namespace The storage namespace
     * @return Quota in bytes
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getStorageQuotaCallback(namespace: String): Long {
        return namespaceQuotas.getOrDefault(namespace, DEFAULT_QUOTA_BYTES)
    }

    /**
     * Set storage quota callback.
     *
     * Sets storage quota for a namespace.
     *
     * @param namespace The storage namespace
     * @param quotaBytes Quota in bytes
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun setStorageQuotaCallback(namespace: String, quotaBytes: Long) {
        namespaceQuotas[namespace] = quotaBytes

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Storage quota set: $namespace = ${quotaBytes / (1024 * 1024)}MB"
        )
    }

    /**
     * Cleanup expired cache callback.
     *
     * Removes expired entries from cache storage.
     *
     * @param maxAgeMs Maximum age in milliseconds
     * @return Number of entries cleaned up
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun cleanupExpiredCacheCallback(maxAgeMs: Long): Int {
        return try {
            var cleanedCount = 0
            val cutoffTime = System.currentTimeMillis() - maxAgeMs

            // Clean up cache storage
            val cacheDir = getStorageDirectory(StorageNamespace.INFERENCE_CACHE, StorageType.CACHE)
            cacheDir.listFiles()?.forEach { file ->
                if (file.lastModified() < cutoffTime) {
                    val size = file.length()
                    if (file.delete()) {
                        cleanedCount++
                        // Update usage
                        val currentUsage = namespaceUsage.getOrDefault(StorageNamespace.INFERENCE_CACHE, 0L)
                        namespaceUsage[StorageNamespace.INFERENCE_CACHE] = maxOf(0L, currentUsage - size)
                    }
                }
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Cleaned up $cleanedCount expired cache entries"
            )

            cleanedCount
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to cleanup expired cache: ${e.message}"
            )
            0
        }
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the storage callbacks with C++ core.
     *
     * C API: rac_storage_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetStorageCallbacks()

    /**
     * Native method to unset the storage callbacks.
     *
     * C API: rac_storage_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetStorageCallbacks()

    /**
     * Native method to store data in C++ storage.
     *
     * C API: rac_storage_store(namespace, key, data, size, type)
     */
    @JvmStatic
    external fun nativeStore(namespace: String, key: String, data: ByteArray, storageType: Int): Int

    /**
     * Native method to retrieve data from C++ storage.
     *
     * C API: rac_storage_retrieve(namespace, key, type)
     */
    @JvmStatic
    external fun nativeRetrieve(namespace: String, key: String, storageType: Int): ByteArray?

    /**
     * Native method to delete data from C++ storage.
     *
     * C API: rac_storage_delete(namespace, key, type)
     */
    @JvmStatic
    external fun nativeDelete(namespace: String, key: String, storageType: Int): Int

    /**
     * Native method to check if data exists in C++ storage.
     *
     * C API: rac_storage_has(namespace, key, type)
     */
    @JvmStatic
    external fun nativeHas(namespace: String, key: String, storageType: Int): Boolean

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the storage callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // TODO: Call native unregistration
            // nativeUnsetStorageCallbacks()

            storageListener = null
            storageProvider = null
            memoryStorage.clear()
            namespaceQuotas.clear()
            namespaceUsage.clear()
            isRegistered = false
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Store data in the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to store under
     * @param data The data to store
     * @param storageType The storage type (default: DISK)
     * @return true if stored successfully
     */
    fun store(
        namespace: String,
        key: String,
        data: ByteArray,
        storageType: Int = StorageType.DISK
    ): Boolean {
        return storeDataCallback(namespace, key, data, storageType) == StorageError.NONE
    }

    /**
     * Store a string in the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to store under
     * @param value The string to store
     * @param storageType The storage type (default: DISK)
     * @return true if stored successfully
     */
    fun storeString(
        namespace: String,
        key: String,
        value: String,
        storageType: Int = StorageType.DISK
    ): Boolean {
        return store(namespace, key, value.toByteArray(Charsets.UTF_8), storageType)
    }

    /**
     * Retrieve data from the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to retrieve
     * @param storageType The storage type (default: DISK)
     * @return The stored data, or null if not found
     */
    fun retrieve(
        namespace: String,
        key: String,
        storageType: Int = StorageType.DISK
    ): ByteArray? {
        return retrieveDataCallback(namespace, key, storageType)
    }

    /**
     * Retrieve a string from the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to retrieve
     * @param storageType The storage type (default: DISK)
     * @return The stored string, or null if not found
     */
    fun retrieveString(
        namespace: String,
        key: String,
        storageType: Int = StorageType.DISK
    ): String? {
        return retrieve(namespace, key, storageType)?.toString(Charsets.UTF_8)
    }

    /**
     * Delete data from the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to delete
     * @param storageType The storage type (default: DISK)
     * @return true if deleted successfully
     */
    fun delete(
        namespace: String,
        key: String,
        storageType: Int = StorageType.DISK
    ): Boolean {
        return deleteDataCallback(namespace, key, storageType) == StorageError.NONE
    }

    /**
     * Check if data exists in the specified namespace.
     *
     * @param namespace The storage namespace
     * @param key The key to check
     * @param storageType The storage type (default: DISK)
     * @return true if data exists
     */
    fun has(
        namespace: String,
        key: String,
        storageType: Int = StorageType.DISK
    ): Boolean {
        return hasDataCallback(namespace, key, storageType)
    }

    /**
     * List all keys in a namespace.
     *
     * @param namespace The storage namespace
     * @param storageType The storage type (default: DISK)
     * @return List of keys
     */
    fun listKeys(
        namespace: String,
        storageType: Int = StorageType.DISK
    ): List<String> {
        val json = listKeysCallback(namespace, storageType)
        // Simple JSON array parsing
        return json.trim()
            .removePrefix("[")
            .removeSuffix("]")
            .split(",")
            .filter { it.isNotBlank() }
            .map { it.trim().removeSurrounding("\"") }
    }

    /**
     * Clear all data in a namespace.
     *
     * @param namespace The storage namespace
     * @param storageType The storage type (default: DISK)
     * @return true if cleared successfully
     */
    fun clear(
        namespace: String,
        storageType: Int = StorageType.DISK
    ): Boolean {
        return clearNamespaceCallback(namespace, storageType) == StorageError.NONE
    }

    /**
     * Get storage usage for a namespace.
     *
     * @param namespace The storage namespace
     * @return Usage in bytes
     */
    fun getUsage(namespace: String): Long {
        return getStorageUsageCallback(namespace)
    }

    /**
     * Get storage quota for a namespace.
     *
     * @param namespace The storage namespace
     * @return Quota in bytes
     */
    fun getQuota(namespace: String): Long {
        return getStorageQuotaCallback(namespace)
    }

    /**
     * Set storage quota for a namespace.
     *
     * @param namespace The storage namespace
     * @param quotaBytes Quota in bytes
     */
    fun setQuota(namespace: String, quotaBytes: Long) {
        setStorageQuotaCallback(namespace, quotaBytes)
    }

    /**
     * Cleanup expired cache entries.
     *
     * @param maxAgeMs Maximum age in milliseconds (default: 7 days)
     * @return Number of entries cleaned up
     */
    fun cleanupExpiredCache(maxAgeMs: Long = DEFAULT_CACHE_EXPIRY_MS): Int {
        return cleanupExpiredCacheCallback(maxAgeMs)
    }

    /**
     * Clear all in-memory storage.
     */
    fun clearMemoryStorage() {
        memoryStorage.clear()
    }

    /**
     * Get the storage file for a key.
     */
    private fun getStorageFile(namespace: String, key: String, storageType: Int): File {
        val dir = getStorageDirectory(namespace, storageType)
        return File(dir, key)
    }

    /**
     * Get the storage directory for a namespace.
     */
    private fun getStorageDirectory(namespace: String, storageType: Int): File {
        val provider = storageProvider
        if (provider != null) {
            return File(provider.getStorageDirectory(namespace, storageType))
        }

        val baseDir = CppBridgeModelPaths.getBaseDirectory()
        val typeDir = when (storageType) {
            StorageType.CACHE -> "cache"
            StorageType.TEMPORARY -> "temp"
            else -> "data"
        }

        return File(File(baseDir, typeDir), namespace)
    }

    /**
     * Initialize default storage quotas.
     */
    private fun initializeDefaultQuotas() {
        namespaceQuotas[StorageNamespace.CONFIG] = 10L * 1024 * 1024      // 10 MB
        namespaceQuotas[StorageNamespace.MODELS] = 50L * 1024 * 1024      // 50 MB
        namespaceQuotas[StorageNamespace.INFERENCE_CACHE] = 100L * 1024 * 1024 // 100 MB
        namespaceQuotas[StorageNamespace.PREFERENCES] = 1L * 1024 * 1024  // 1 MB
        namespaceQuotas[StorageNamespace.SESSION] = 10L * 1024 * 1024     // 10 MB
        namespaceQuotas[StorageNamespace.ANALYTICS] = 20L * 1024 * 1024   // 20 MB
        namespaceQuotas[StorageNamespace.DOWNLOADS] = 10L * 1024 * 1024   // 10 MB
    }

    /**
     * Escape special characters for JSON string.
     */
    private fun escapeJson(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }
}
