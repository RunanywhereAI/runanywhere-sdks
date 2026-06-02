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

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import java.io.File

/**
 * One directory entry returned by [CppBridgePlatformAdapter.fileListDirectory].
 *
 * Mirrors `rac_directory_entry_t` in
 * `sdk/runanywhere-commons/include/rac/core/rac_platform_adapter.h`. The
 * JNI layer reflects on the field names ([name], [isDir], [sizeBytes]) so
 * keep the property names in sync with the FieldID lookups in
 * `runanywhere_commons_jni.cpp::jni_file_list_directory_callback`.
 *
 * @property name UTF-8 entry name (no path component). MUST fit in
 *                [CppBridgePlatformAdapter.NAME_MAX_BYTES] including the
 *                trailing NUL byte that the JNI layer appends; oversized
 *                entries MUST be filtered by the producer (we do this in
 *                [CppBridgePlatformAdapter.fileListDirectory]).
 * @property isDir true when the entry is a directory.
 * @property sizeBytes file size in bytes; 0 for directories or unknown.
 */
data class RacDirectoryEntry(
    @JvmField val name: String,
    @JvmField val isDir: Boolean,
    @JvmField val sizeBytes: Long,
)

/**
 * Platform adapter that provides JNI callbacks for C++ core operations.
 *
 * CRITICAL: This MUST be registered FIRST before any C++ calls.
 * The host app MUST configure a [PlatformSecureStorage] via [setPlatformStorage]
 * (or [setContext] on Android) before any secure-storage callback is invoked.
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
     * Maximum byte length (including the trailing NUL) of an entry name
     * returned via [RacDirectoryEntry]. Mirrors
     * `RAC_DIRECTORY_ENTRY_NAME_MAX` in `rac_platform_adapter.h`.
     *
     * Per the truncation contract on `rac_directory_entry_t::name`,
     * oversized entries MUST be skipped rather than truncated so the
     * no-error path never returns a half-name that could alias a
     * different on-disk artifact.
     */
    const val NAME_MAX_BYTES: Int = 512

    /**
     * Platform-specific storage delegate. MUST be set before any secure-storage
     * callback is invoked. On Android, use `setContext` (defined in
     * `com.runanywhere.sdk.foundation.security`) which installs an
     * AndroidKeyStore-backed implementation.
     */
    @Volatile
    private var platformStorage: PlatformSecureStorage? = null

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridge"

    /**
     * Fetch the configured [PlatformSecureStorage].
     *
     * Android consumers MUST call [setContext] (or [setPlatformStorage] directly)
     * before any secure-storage callback is invoked. This SDK is Android-only;
     * there is no automatic fallback.
     */
    private fun requirePlatformStorage(): PlatformSecureStorage {
        platformStorage?.let { return it }
        synchronized(lock) {
            platformStorage?.let { return it }
        }
        throw IllegalStateException(
            "Platform secure storage not configured — call RunAnywhere.setPlatformStorage() before use",
        )
    }

    /**
     * Interface for platform-specific secure storage.
     * Implemented differently on Android vs JVM.
     */
    interface PlatformSecureStorage {
        fun get(key: String): ByteArray?

        fun set(key: String, value: ByteArray): Boolean

        fun delete(key: String): Boolean

        fun clear()
    }

    /**
     * Set the platform-specific storage implementation.
     * On Android, this should be called with an AndroidKeychainManager instance.
     *
     * @param storage The platform storage implementation
     */
    fun setPlatformStorage(storage: PlatformSecureStorage) {
        synchronized(lock) {
            platformStorage = storage
            logCallback(LogLevel.DEBUG, TAG, "Platform storage initialized for persistent storage")
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

            val result = RunAnywhereBridge.racSetPlatformAdapter(this)
            if (result != 0) {
                logCallback(LogLevel.ERROR, TAG, "Failed to set platform adapter: $result")
                return
            }

            isRegistered = true
        }
    }

    /**
     * Check if the platform adapter is registered.
     */
    fun isRegistered(): Boolean = isRegistered

    // Logging callbacks

    /**
     * Log callback for C++ core.
     *
     * Routes C++ log messages to Kotlin logging system.
     * Parses structured metadata from C++ log messages.
     *
     * Format: "Message text | key1=value1, key2=value2"
     *
     * @param level The log level (see [LogLevel] constants)
     * @param tag The log tag/category
     * @param message The log message (may contain metadata)
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun logCallback(level: Int, tag: String, message: String) {
        // Parse structured metadata from C++ log messages
        val (cleanMessage, metadata) = parseLogMetadata(message)
        val category = if (tag.isNotEmpty()) tag else "RAC"

        // Native ERROR/FATAL goes directly to logcat too. SDKLogger routes
        // through println(System.out) which is unreliable on release builds
        // and gated by enableLocalLogging — this guarantees diagnostic logs
        // survive config or redirection issues.
        if (level >= LogLevel.ERROR) {
            android.util.Log.e(category, cleanMessage)
        }

        // Create logger with proper category for destination routing
        val logger = SDKLogger(category)

        when (level) {
            LogLevel.TRACE -> logger.trace("[Native] $cleanMessage", metadata)
            LogLevel.DEBUG -> logger.debug("[Native] $cleanMessage", metadata)
            LogLevel.INFO -> logger.info("[Native] $cleanMessage", metadata)
            LogLevel.WARN -> logger.warning("[Native] $cleanMessage", metadata)
            LogLevel.ERROR -> logger.error("[Native] $cleanMessage", metadata)
            LogLevel.FATAL -> logger.fault("[Native] $cleanMessage", metadata)
            else -> logger.debug("[Native] $cleanMessage", metadata)
        }
    }

    /**
     * Parse structured metadata from C++ log messages.
     *
     * Format: "Message text | key1=value1, key2=value2"
     *
     * Matches iOS SDK's parseLogMetadata function in CppBridge+PlatformAdapter.swift
     *
     * @param message The raw log message from C++
     * @return Pair of (clean message, metadata map)
     */
    private fun parseLogMetadata(message: String): Pair<String, Map<String, Any?>?> {
        val parts = message.split(" | ", limit = 2)
        if (parts.size < 2) {
            return Pair(message, null)
        }

        val cleanMessage = parts[0]
        val metadataString = parts[1]

        val metadata = mutableMapOf<String, Any?>()
        val pairs =
            metadataString
                .split(Regex("[,\\s]+"))
                .filter { it.isNotEmpty() && it.contains("=") }

        for (pair in pairs) {
            val keyValue = pair.split("=", limit = 2)
            if (keyValue.size != 2) continue

            val key = keyValue[0].trim()
            val value = keyValue[1].trim()

            // Map known C++ keys to SDK metadata keys (matching iOS behavior)
            when (key) {
                "file" -> metadata["source_file"] = value
                "func" -> metadata["source_function"] = value
                "error_code" -> metadata["error_code"] = value.toIntOrNull() ?: value
                "error" -> metadata["error_message"] = value
                "model" -> metadata["model_id"] = value
                "framework" -> metadata["framework"] = value
                else -> metadata[key] = value
            }
        }

        return Pair(cleanMessage, metadata.ifEmpty { null })
    }

    // File operation callbacks

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

    // Directory enumeration callbacks (kotlin-005-C)
    //
    // Populate the `file_list_directory` and `is_non_empty_directory` slots
    // in `rac_platform_adapter_t` so model-registry refresh (`rescan_local`)
    // and `rac_model_info_make_proto`'s `is_downloaded` probe for multi-file
    // artifacts both work on Android the same way they do on Web/iOS. See
    // the per-slot doc-blocks in
    // `sdk/runanywhere-commons/include/rac/core/rac_platform_adapter.h`.

    /**
     * Enumerate the entries in [dirPath] for the commons platform adapter.
     *
     * Returns null when the directory does not exist (mapped to
     * RAC_ERROR_FILE_NOT_FOUND in the JNI layer). On other failures we log
     * and return an empty array so commons treats the directory as empty
     * rather than crashing the rescan / is_downloaded path.
     *
     * Truncation contract (per `rac_directory_entry_t::name`): entries
     * whose UTF-8 byte length plus the trailing NUL exceed
     * [NAME_MAX_BYTES] MUST be skipped rather than silently truncated. We
     * emit a single WARN log per call that summarises how many entries
     * were skipped so operators can detect the rare event without flooding
     * logcat.
     */
    @JvmStatic
    fun fileListDirectoryCallback(dirPath: String): Array<RacDirectoryEntry>? {
        val dir =
            try {
                File(dirPath)
            } catch (e: Exception) {
                logCallback(LogLevel.ERROR, "FileOps", "fileListDirectory invalid path '$dirPath': ${e.message}")
                return emptyArray()
            }
        if (!dir.exists() || !dir.isDirectory) {
            // Mirror the C ABI contract: null signals RAC_ERROR_FILE_NOT_FOUND.
            return null
        }
        return try {
            // listFiles() returns null on I/O errors (permission denied,
            // disk error, etc.). Treat that as "empty directory" so commons
            // can continue rather than abort the whole rescan.
            val children = dir.listFiles() ?: return emptyArray()
            val retained = ArrayList<RacDirectoryEntry>(children.size)
            var skipped = 0
            for (child in children) {
                val nameBytes = child.name.toByteArray(Charsets.UTF_8)
                if (nameBytes.size + 1 > NAME_MAX_BYTES) {
                    skipped++
                    continue
                }
                val isDir = child.isDirectory
                val sizeBytes = if (isDir) 0L else runCatching { child.length() }.getOrDefault(0L)
                retained.add(RacDirectoryEntry(child.name, isDir, sizeBytes))
            }
            if (skipped > 0) {
                logCallback(
                    LogLevel.WARN,
                    "PlatformAdapter",
                    "Skipped $skipped directory entries in '$dirPath': name longer than " +
                        "$NAME_MAX_BYTES bytes (truncation contract).",
                )
            }
            retained.toTypedArray()
        } catch (e: SecurityException) {
            // SecurityManager / Android scoped-storage denial. Surface as
            // "empty" rather than RAC_ERROR_FILE_NOT_FOUND so commons does
            // not treat a permission miss as a missing directory.
            logCallback(LogLevel.WARN, "FileOps", "fileListDirectory denied for '$dirPath': ${e.message}")
            emptyArray()
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "FileOps", "fileListDirectory failed for '$dirPath': ${e.message}")
            emptyArray()
        }
    }

    /**
     * Cheap directory-probe — RAC_TRUE iff [path] is a directory containing
     * at least one entry. Commons uses this from `rac_model_info_make_proto`
     * to compute the `is_downloaded` flag for multi-file artifacts without
     * paying for a full enumeration.
     */
    @JvmStatic
    fun isNonEmptyDirectoryCallback(path: String): Boolean {
        return try {
            val dir = File(path)
            if (!dir.exists() || !dir.isDirectory) {
                return false
            }
            // listFiles() returns null on I/O / permission errors — treat
            // those as "not non-empty" to match the conservative C
            // contract: a false negative degrades to is_downloaded=false,
            // which is safer than a false positive.
            val children = dir.listFiles()
            children != null && children.isNotEmpty()
        } catch (e: Exception) {
            logCallback(LogLevel.WARN, "FileOps", "isNonEmptyDirectory failed for '$path': ${e.message}")
            false
        }
    }

    // Secure storage callbacks

    /**
     * Get a value from secure storage.
     *
     * Requires a [PlatformSecureStorage] to be configured via [setPlatformStorage]
     * (or [setContext] on Android). There is no in-memory fallback by design.
     *
     * @param key The key to retrieve
     * @return The stored value as ByteArray, or null if not found
     * @throws IllegalStateException if platform secure storage is not configured
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun secureGetCallback(key: String): ByteArray? {
        val storage = requirePlatformStorage()
        return try {
            storage.get(key)
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "SecureStorage", "secureGet failed for key '$key': ${e.message}")
            null
        }
    }

    /**
     * Store a value in secure storage.
     *
     * Requires a [PlatformSecureStorage] to be configured via [setPlatformStorage]
     * (or [setContext] on Android). There is no in-memory fallback by design.
     *
     * @param key The key to store under
     * @param value The value to store
     * @return true if storage succeeded, false otherwise
     * @throws IllegalStateException if platform secure storage is not configured
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun secureSetCallback(key: String, value: ByteArray): Boolean {
        val storage = requirePlatformStorage()
        return try {
            val ok = storage.set(key, value)
            if (ok) {
                logCallback(LogLevel.DEBUG, "SecureStorage", "Persisted key '$key' to platform storage")
            }
            ok
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "SecureStorage", "secureSet failed for key '$key': ${e.message}")
            false
        }
    }

    /**
     * Delete a value from secure storage.
     *
     * Requires a [PlatformSecureStorage] to be configured via [setPlatformStorage]
     * (or [setContext] on Android). There is no in-memory fallback by design.
     *
     * @param key The key to delete
     * @return true if delete succeeded or key didn't exist, false otherwise
     * @throws IllegalStateException if platform secure storage is not configured
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun secureDeleteCallback(key: String): Boolean {
        val storage = requirePlatformStorage()
        return try {
            storage.delete(key)
            true
        } catch (e: Exception) {
            logCallback(LogLevel.ERROR, "SecureStorage", "secureDelete failed for key '$key': ${e.message}")
            false
        }
    }

    // Clock callbacks

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

    // Platform HTTP byte execution is registered through CppBridgeHTTP.
    // Download workflow planning/progress/state now flows through generated
    // Download* proto calls; direct HTTP callbacks here remain intentionally
    // absent from the platform adapter surface.

    // Instance methods required by the JNI platform adapter

    fun log(level: Int, tag: String, message: String) {
        logCallback(level, tag, message)
    }

    fun fileExists(path: String): Boolean = fileExistsCallback(path)

    fun fileRead(path: String): ByteArray? = fileReadCallback(path)

    fun fileWrite(path: String, data: ByteArray): Boolean = fileWriteCallback(path, data)

    fun fileDelete(path: String): Boolean = fileDeleteCallback(path)

    // JNI looks these up via GetMethodID in racSetPlatformAdapter — keep the
    // signatures and the RacDirectoryEntry FQCN in sync with
    // `runanywhere_commons_jni.cpp::racSetPlatformAdapter`.
    fun fileListDirectory(dirPath: String): Array<RacDirectoryEntry>? = fileListDirectoryCallback(dirPath)

    fun isNonEmptyDirectory(path: String): Boolean = isNonEmptyDirectoryCallback(path)

    fun secureGet(key: String): String? {
        val value = secureGetCallback(key) ?: return null
        return String(value, Charsets.UTF_8)
    }

    fun secureSet(key: String, value: String): Boolean = secureSetCallback(key, value.toByteArray(Charsets.UTF_8))

    fun secureDelete(key: String): Boolean = secureDeleteCallback(key)

    fun nowMs(): Long = nowMsCallback()

    // JNI native declarations

    // Lifecycle management

    /**
     * Unregister the platform adapter.
     *
     * Called during SDK shutdown.
     * Note: Does NOT clear persistent storage (device ID should survive SDK restarts).
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }
            isRegistered = false
        }
    }

    /**
     * Clear all secure storage entries via the configured [PlatformSecureStorage].
     *
     * WARNING: This clears the device ID! Device will be re-registered on next app start.
     * Useful for testing or when user requests data deletion.
     *
     * @throws IllegalStateException if platform secure storage is not configured
     */
    fun clearSecureStorage() {
        requirePlatformStorage().clear()
        logCallback(LogLevel.INFO, "SecureStorage", "All secure storage cleared")
    }
}
