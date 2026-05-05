/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM-specific secure storage implementation using AES-GCM 256 encryption
 * with file-per-key persistence under ~/.runanywhere/secure/.
 *
 * Mirrors iOS KeychainManager's role (encrypted persistent key-value store)
 * and AndroidSecureStorage's PlatformSecureStorage contract, but targets
 * desktop JVM where no platform keychain is guaranteed.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.PosixFilePermission
import java.nio.file.attribute.PosixFilePermissions
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.locks.ReentrantLock
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.concurrent.withLock

/**
 * JVM implementation of [CppBridgePlatformAdapter.PlatformSecureStorage] that
 * persists entries as AES-GCM 256 encrypted files under the user's home directory.
 *
 * Layout:
 * - `~/.runanywhere/secure/.masterkey` — 32-byte raw AES-256 master key (0600 on POSIX)
 * - `~/.runanywhere/secure/<urlSafeBase64(key)>` — one file per entry, format:
 *   `[iv (12B)][ciphertext + GCM auth tag (16B trailing)]`
 *
 * Thread-safe via a single [ReentrantLock] guarding all file and cipher operations.
 */
class JvmSecureStorage(
    baseDirectory: File = defaultBaseDirectory(),
) : CppBridgePlatformAdapter.PlatformSecureStorage {
    private val logger = SDKLogger(LOG_TAG)
    private val lock = ReentrantLock()
    private val secureRandom = SecureRandom()
    private val storageDir: File = baseDirectory
    private val masterKeyFile: File = File(storageDir, MASTER_KEY_FILENAME)
    private val masterKey: SecretKeySpec

    init {
        ensureStorageDirectory()
        masterKey = SecretKeySpec(loadOrCreateMasterKey(), AES_ALGORITHM)
    }

    override fun get(key: String): ByteArray? {
        return lock.withLock {
            val file = fileFor(key)
            if (!file.exists()) {
                return@withLock null
            }
            try {
                val payload = file.readBytes()
                if (payload.size <= GCM_IV_LENGTH) {
                    logger.warning("Secure storage payload for key '$key' is truncated (${payload.size} bytes)")
                    return@withLock null
                }
                val iv = payload.copyOfRange(0, GCM_IV_LENGTH)
                val ciphertext = payload.copyOfRange(GCM_IV_LENGTH, payload.size)
                val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
                cipher.init(Cipher.DECRYPT_MODE, masterKey, GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
                cipher.doFinal(ciphertext)
            } catch (e: Exception) {
                logger.error("Secure storage decrypt failed for key '$key'", throwable = e)
                null
            }
        }
    }

    override fun set(key: String, value: ByteArray): Boolean {
        return lock.withLock {
            try {
                val iv = ByteArray(GCM_IV_LENGTH).also { secureRandom.nextBytes(it) }
                val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
                cipher.init(Cipher.ENCRYPT_MODE, masterKey, GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
                val ciphertext = cipher.doFinal(value)
                val payload = ByteArray(iv.size + ciphertext.size)
                System.arraycopy(iv, 0, payload, 0, iv.size)
                System.arraycopy(ciphertext, 0, payload, iv.size, ciphertext.size)
                writeFileAtomically(fileFor(key).toPath(), payload)
                true
            } catch (e: Exception) {
                logger.error("Secure storage encrypt failed for key '$key'", throwable = e)
                false
            }
        }
    }

    override fun delete(key: String): Boolean {
        return lock.withLock {
            try {
                val file = fileFor(key)
                if (!file.exists()) {
                    return@withLock true
                }
                file.delete()
            } catch (e: Exception) {
                logger.error("Secure storage delete failed for key '$key'", throwable = e)
                false
            }
        }
    }

    override fun clear() {
        lock.withLock {
            try {
                val entries = storageDir.listFiles() ?: return@withLock
                for (entry in entries) {
                    if (entry.name == MASTER_KEY_FILENAME) {
                        continue
                    }
                    if (!entry.delete()) {
                        logger.warning("Secure storage clear failed to delete '${entry.name}'")
                    }
                }
            } catch (e: Exception) {
                logger.error("Secure storage clear failed", throwable = e)
            }
        }
    }

    // ------------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------------

    private fun fileFor(key: String): File {
        val encoded = Base64.getUrlEncoder().withoutPadding().encodeToString(key.toByteArray(Charsets.UTF_8))
        return File(storageDir, encoded)
    }

    private fun ensureStorageDirectory() {
        if (storageDir.exists()) {
            return
        }
        if (!storageDir.mkdirs()) {
            throw IllegalStateException("Failed to create secure storage directory: ${storageDir.absolutePath}")
        }
        restrictDirectoryPermissions(storageDir.toPath())
    }

    private fun loadOrCreateMasterKey(): ByteArray {
        if (masterKeyFile.exists()) {
            val bytes = masterKeyFile.readBytes()
            if (bytes.size == MASTER_KEY_BYTES) {
                return bytes
            }
            logger.warning("Master key file has unexpected size ${bytes.size}; regenerating")
        }
        val fresh = ByteArray(MASTER_KEY_BYTES).also { secureRandom.nextBytes(it) }
        writeFileAtomically(masterKeyFile.toPath(), fresh)
        restrictFilePermissions(masterKeyFile.toPath())
        return fresh
    }

    private fun writeFileAtomically(target: Path, data: ByteArray) {
        val parent = target.parent ?: throw IllegalStateException("Secure storage target has no parent: $target")
        val tmp = Files.createTempFile(parent, TEMP_FILE_PREFIX, TEMP_FILE_SUFFIX)
        try {
            Files.write(tmp, data)
            restrictFilePermissions(tmp)
            try {
                Files.move(tmp, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (e: UnsupportedOperationException) {
                // Some filesystems (e.g. Windows FAT32) don't support atomic moves; fall back.
                logger.debug("Atomic move unsupported on this filesystem; falling back to replace-existing move: ${e.message}")
                Files.move(tmp, target, StandardCopyOption.REPLACE_EXISTING)
            }
            restrictFilePermissions(target)
        } finally {
            Files.deleteIfExists(tmp)
        }
    }

    private fun restrictFilePermissions(path: Path) {
        if (!supportsPosixPermissions(path)) {
            // On Windows, rely on user-profile ACL inheritance. Nothing extra to do here.
            return
        }
        try {
            Files.setPosixFilePermissions(path, OWNER_READ_WRITE_PERMISSIONS)
        } catch (e: Exception) {
            logger.warning("Failed to restrict POSIX permissions on '$path': ${e.message}")
        }
    }

    private fun restrictDirectoryPermissions(path: Path) {
        if (!supportsPosixPermissions(path)) {
            return
        }
        try {
            Files.setPosixFilePermissions(path, OWNER_READ_WRITE_EXECUTE_PERMISSIONS)
        } catch (e: Exception) {
            logger.warning("Failed to restrict POSIX permissions on directory '$path': ${e.message}")
        }
    }

    private fun supportsPosixPermissions(path: Path): Boolean {
        return try {
            path.fileSystem.supportedFileAttributeViews().contains(POSIX_ATTRIBUTE_VIEW)
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private const val LOG_TAG = "JvmSecureStorage"
        private const val AES_ALGORITHM = "AES"
        private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_LENGTH_BITS = 128
        private const val MASTER_KEY_BYTES = 32
        private const val MASTER_KEY_FILENAME = ".masterkey"
        private const val SECURE_STORAGE_SUBDIR = ".runanywhere/secure"
        private const val TEMP_FILE_PREFIX = ".runanywhere-tmp-"
        private const val TEMP_FILE_SUFFIX = ".bin"
        private const val USER_HOME_PROPERTY = "user.home"
        private const val POSIX_ATTRIBUTE_VIEW = "posix"

        private val OWNER_READ_WRITE_PERMISSIONS: Set<PosixFilePermission> =
            PosixFilePermissions.fromString("rw-------")
        private val OWNER_READ_WRITE_EXECUTE_PERMISSIONS: Set<PosixFilePermission> =
            PosixFilePermissions.fromString("rwx------")

        /**
         * Default storage directory: `~/.runanywhere/secure/`.
         */
        fun defaultBaseDirectory(): File {
            val userHome =
                System.getProperty(USER_HOME_PROPERTY)
                    ?: throw IllegalStateException("System property '$USER_HOME_PROPERTY' is not set")
            return File(userHome, SECURE_STORAGE_SUBDIR)
        }
    }
}

/**
 * Extension function to install a [JvmSecureStorage] on the platform adapter.
 *
 * This is the recommended entry point for JVM desktop consumers and mirrors
 * [CppBridgePlatformAdapter.setContext] on Android.
 *
 * @param baseDirectory Override the storage directory; defaults to `~/.runanywhere/secure/`.
 */
fun CppBridgePlatformAdapter.installJvmSecureStorage(
    baseDirectory: File = JvmSecureStorage.defaultBaseDirectory(),
) {
    setPlatformStorage(JvmSecureStorage(baseDirectory))
}
