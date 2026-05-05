/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android-specific secure storage implementation using EncryptedSharedPreferences
 * (AndroidX Security Crypto) backed by the Android Keystore (AES-256-GCM values,
 * AES-256-SIV keys, 256-bit AES-GCM master key).
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.runanywhere.sdk.foundation.SDKLogger
import java.io.File

/**
 * Android implementation of [CppBridgePlatformAdapter.PlatformSecureStorage] using
 * [EncryptedSharedPreferences]. Values are encrypted at rest with AES-256-GCM and
 * keys with AES-256-SIV using a master key held in the Android Keystore.
 *
 * On first use this instance also performs a one-shot migration from the legacy
 * plaintext/Base64 `SharedPreferences` store written by earlier SDK versions; the
 * legacy file is cleared and deleted after a successful migration so no plaintext
 * copy is left on disk.
 *
 * @param context Any Android context; only [Context.getApplicationContext] is retained.
 */
class AndroidSecureStorage(
    context: Context,
) : CppBridgePlatformAdapter.PlatformSecureStorage {
    private val appContext: Context = context.applicationContext
    private val logger = SDKLogger(LOG_CATEGORY)

    private val encryptedPreferences: SharedPreferences by lazy {
        val masterKey =
            MasterKey
                .Builder(appContext)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
        EncryptedSharedPreferences.create(
            appContext,
            ENCRYPTED_PREFS_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    /**
     * Tracks whether the one-shot legacy migration has already executed in this
     * process. Uses a structured [MigrationState] rather than a boolean/string
     * to keep intent explicit and extendable.
     */
    @Volatile
    private var migrationState: MigrationState = MigrationState.Pending

    /**
     * Structured migration state marker. Prevents us from using raw boolean/string
     * flags and keeps the lifecycle legible.
     */
    private sealed class MigrationState {
        object Pending : MigrationState()

        object Completed : MigrationState()
    }

    override fun get(key: String): ByteArray? {
        ensureMigrated()
        val stored = encryptedPreferences.getString(key, null) ?: return null
        return stored.toByteArray(Charsets.ISO_8859_1)
    }

    override fun set(key: String, value: ByteArray): Boolean {
        ensureMigrated()
        return try {
            encryptedPreferences
                .edit()
                .putString(key, String(value, Charsets.ISO_8859_1))
                .apply()
            true
        } catch (t: Throwable) {
            logger.error("Failed to write encrypted entry for key '$key': ${t.message}")
            false
        }
    }

    override fun delete(key: String): Boolean {
        ensureMigrated()
        encryptedPreferences.edit().remove(key).apply()
        return true
    }

    override fun clear() {
        ensureMigrated()
        encryptedPreferences.edit().clear().apply()
    }

    /**
     * Run the one-shot legacy → encrypted migration if it has not executed yet.
     * Guarded by `synchronized(migrationLock)` so concurrent callers never race
     * into running the migration twice.
     */
    private fun ensureMigrated() {
        if (migrationState is MigrationState.Completed) return
        synchronized(migrationLock) {
            if (migrationState is MigrationState.Completed) return
            migrateLegacyStoreIfPresent()
            migrationState = MigrationState.Completed
        }
    }

    /**
     * Read entries from the pre-0.19.x plaintext+Base64 preferences file (if any),
     * rewrite them into [encryptedPreferences], then clear and delete the legacy
     * file so no plaintext copy remains.
     */
    private fun migrateLegacyStoreIfPresent() {
        val legacyFile = legacyPreferencesFile(appContext)
        if (!legacyFile.exists() || legacyFile.length() == 0L) {
            return
        }

        val legacyPrefs =
            appContext.getSharedPreferences(
                LEGACY_PREFS_NAME,
                Context.MODE_PRIVATE,
            )
        val legacyEntries = legacyPrefs.all
        if (legacyEntries.isEmpty()) {
            clearAndDeleteLegacy(legacyPrefs, legacyFile, migratedCount = 0)
            return
        }

        var migrated = 0
        val encryptedEditor = encryptedPreferences.edit()
        for ((entryKey, entryValue) in legacyEntries) {
            val base64Encoded = entryValue as? String ?: continue
            val rawBytes =
                try {
                    android.util.Base64.decode(base64Encoded, android.util.Base64.NO_WRAP)
                } catch (t: Throwable) {
                    logger.warning(
                        "Skipping unreadable legacy entry '$entryKey' during migration: ${t.message}",
                    )
                    continue
                }
            encryptedEditor.putString(entryKey, String(rawBytes, Charsets.ISO_8859_1))
            migrated++
        }
        encryptedEditor.apply()

        clearAndDeleteLegacy(legacyPrefs, legacyFile, migratedCount = migrated)
    }

    private fun clearAndDeleteLegacy(
        legacyPrefs: SharedPreferences,
        legacyFile: File,
        migratedCount: Int,
    ) {
        legacyPrefs.edit().clear().apply()
        val deleted = legacyFile.delete()
        logger.info(
            "Migrated $migratedCount entries from legacy plaintext secure-storage to " +
                "EncryptedSharedPreferences; legacy file deleted=$deleted",
        )
    }

    companion object {
        /** Filename of the new AES-GCM/SIV encrypted preferences store. */
        private const val ENCRYPTED_PREFS_NAME = "runanywhere_secure_storage_encrypted"

        /** Legacy plaintext-Base64 filename used by SDK versions <= 0.19.x. */
        private const val LEGACY_PREFS_NAME = "runanywhere_secure_storage"

        /** Logger category for secure-storage operations. */
        private const val LOG_CATEGORY = "SecureStorage"

        /**
         * Process-wide lock guarding the one-shot legacy migration. Lives in the
         * companion so multiple [AndroidSecureStorage] instances against the same
         * application context share the same serialization point.
         */
        private val migrationLock = Any()

        /**
         * SharedPreferences files are stored under `<app>/shared_prefs/<name>.xml`.
         * We resolve the path via the appContext so tests using an instrumented
         * context still see the right directory.
         */
        private fun legacyPreferencesFile(appContext: Context): File {
            val prefsDir = File(appContext.applicationInfo.dataDir, "shared_prefs")
            return File(prefsDir, "$LEGACY_PREFS_NAME.xml")
        }
    }
}

/**
 * Extension function to easily set Android context for CppBridgePlatformAdapter.
 * This is the recommended way to initialize storage on Android.
 *
 * @param context The Android context (will use applicationContext internally)
 */
fun CppBridgePlatformAdapter.setContext(context: Context) {
    setPlatformStorage(AndroidSecureStorage(context))
}
