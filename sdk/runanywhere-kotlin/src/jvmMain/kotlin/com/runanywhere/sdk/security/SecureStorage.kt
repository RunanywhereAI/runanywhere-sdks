package com.runanywhere.sdk.security

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.file.Files
import java.nio.file.Paths
import java.security.SecureRandom
import java.util.*
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

/**
 * JVM implementation of SecureStorage using encrypted file storage
 * Uses AES-GCM encryption with a locally generated key
 * For production JVM applications, consider integrating with system keystore
 */
@OptIn(ExperimentalEncodingApi::class)
class JvmSecureStorage private constructor(
    private val storageDir: File,
    private val identifier: String,
    private val secretKey: SecretKey
) : SecureStorage {

    private val logger = SDKLogger("JvmSecureStorage")
    private val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    private val gcmTagLength = 16
    private val ivLength = 12

    companion object {
        private val storageInstances = mutableMapOf<String, JvmSecureStorage>()

        /**
         * Create secure storage instance for JVM
         */
        fun create(identifier: String): JvmSecureStorage {
            // Return cached instance if available
            storageInstances[identifier]?.let { return it }

            try {
                // Create storage directory
                val userHome = System.getProperty("user.home")
                val storageDir = File(userHome, ".runanywhere-sdk/$identifier")
                if (!storageDir.exists()) {
                    storageDir.mkdirs()
                }

                // Load or create encryption key
                val secretKey = loadOrCreateKey(storageDir)

                val storage = JvmSecureStorage(storageDir, identifier, secretKey)
                storageInstances[identifier] = storage
                return storage

            } catch (e: Exception) {
                throw SDKError.SecurityError("Failed to create JVM secure storage: ${e.message}")
            }
        }

        /**
         * Load existing encryption key or create a new one
         */
        private fun loadOrCreateKey(storageDir: File): SecretKey {
            val keyFile = File(storageDir, ".encryption_key")

            return if (keyFile.exists()) {
                try {
                    val keyBytes = keyFile.readBytes()
                    SecretKeySpec(keyBytes, "AES")
                } catch (e: Exception) {
                    // If key loading fails, create a new one
                    createAndSaveKey(keyFile)
                }
            } else {
                createAndSaveKey(keyFile)
            }
        }

        /**
         * Create and save a new encryption key
         */
        private fun createAndSaveKey(keyFile: File): SecretKey {
            val keyGenerator = KeyGenerator.getInstance("AES")
            keyGenerator.init(256) // 256-bit AES key
            val secretKey = keyGenerator.generateKey()

            // Save key to file with restricted permissions
            keyFile.writeBytes(secretKey.encoded)

            // Set file permissions to be readable only by owner (Unix-like systems)
            try {
                val path = keyFile.toPath()
                Files.setPosixFilePermissions(path, setOf(
                    java.nio.file.attribute.PosixFilePermission.OWNER_READ,
                    java.nio.file.attribute.PosixFilePermission.OWNER_WRITE
                ))
            } catch (e: Exception) {
                // Ignore on Windows or if POSIX permissions are not supported
            }

            return secretKey
        }

        /**
         * Check if JVM secure storage is supported
         */
        fun isSupported(): Boolean {
            return try {
                // Check if we can create directories and files
                val testDir = File(System.getProperty("user.home"), ".runanywhere-sdk-test")
                testDir.mkdirs()
                val canWrite = testDir.canWrite()
                testDir.deleteRecursively()
                canWrite
            } catch (e: Exception) {
                false
            }
        }
    }

    override suspend fun setSecureString(key: String, value: String) = withContext(Dispatchers.IO) {
        try {
            val encryptedData = encrypt(value.toByteArray())
            val file = File(storageDir, "${key}.enc")
            file.writeBytes(encryptedData)
            logger.debug("Stored secure string for key: $key")
        } catch (e: Exception) {
            logger.error("Failed to store secure string for key: $key", e)
            throw SDKError.SecurityError("Failed to store secure data: ${e.message}")
        }
    }

    override suspend fun getSecureString(key: String): String? = withContext(Dispatchers.IO) {
        try {
            val file = File(storageDir, "${key}.enc")
            if (!file.exists()) return@withContext null

            val encryptedData = file.readBytes()
            val decryptedData = decrypt(encryptedData)
            val value = String(decryptedData)
            logger.debug("Retrieved secure string for key: $key")
            value
        } catch (e: Exception) {
            logger.error("Failed to retrieve secure string for key: $key", e)
            throw SDKError.SecurityError("Failed to retrieve secure data: ${e.message}")
        }
    }

    override suspend fun setSecureData(key: String, data: ByteArray) = withContext(Dispatchers.IO) {
        try {
            val encryptedData = encrypt(data)
            val file = File(storageDir, "${key}.bin.enc")
            file.writeBytes(encryptedData)
            logger.debug("Stored secure data for key: $key (${data.size} bytes)")
        } catch (e: Exception) {
            logger.error("Failed to store secure data for key: $key", e)
            throw SDKError.SecurityError("Failed to store secure data: ${e.message}")
        }
    }

    override suspend fun getSecureData(key: String): ByteArray? = withContext(Dispatchers.IO) {
        try {
            val file = File(storageDir, "${key}.bin.enc")
            if (!file.exists()) return@withContext null

            val encryptedData = file.readBytes()
            val decryptedData = decrypt(encryptedData)
            logger.debug("Retrieved secure data for key: $key (${decryptedData.size} bytes)")
            decryptedData
        } catch (e: Exception) {
            logger.error("Failed to retrieve secure data for key: $key", e)
            throw SDKError.SecurityError("Failed to retrieve secure data: ${e.message}")
        }
    }

    override suspend fun removeSecure(key: String) = withContext(Dispatchers.IO) {
        try {
            val stringFile = File(storageDir, "${key}.enc")
            val dataFile = File(storageDir, "${key}.bin.enc")

            var removed = false
            if (stringFile.exists()) {
                stringFile.delete()
                removed = true
            }
            if (dataFile.exists()) {
                dataFile.delete()
                removed = true
            }

            if (removed) {
                logger.debug("Removed secure data for key: $key")
            }
        } catch (e: Exception) {
            logger.error("Failed to remove secure data for key: $key", e)
            throw SDKError.SecurityError("Failed to remove secure data: ${e.message}")
        }
    }

    override suspend fun containsKey(key: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val stringFile = File(storageDir, "${key}.enc")
            val dataFile = File(storageDir, "${key}.bin.enc")
            stringFile.exists() || dataFile.exists()
        } catch (e: Exception) {
            logger.error("Failed to check key existence: $key", e)
            false
        }
    }

    override suspend fun clearAll() = withContext(Dispatchers.IO) {
        try {
            storageDir.listFiles()?.forEach { file ->
                if (file.name.endsWith(".enc")) {
                    file.delete()
                }
            }
            logger.info("Cleared all secure data")
        } catch (e: Exception) {
            logger.error("Failed to clear all secure data", e)
            throw SDKError.SecurityError("Failed to clear secure data: ${e.message}")
        }
    }

    override suspend fun getAllKeys(): Set<String> = withContext(Dispatchers.IO) {
        try {
            storageDir.listFiles()
                ?.filter { it.name.endsWith(".enc") }
                ?.map {
                    it.name.removeSuffix(".enc").removeSuffix(".bin")
                }
                ?.toSet() ?: emptySet()
        } catch (e: Exception) {
            logger.error("Failed to get all keys", e)
            emptySet()
        }
    }

    override suspend fun isAvailable(): Boolean = withContext(Dispatchers.IO) {
        try {
            // Test by trying to encrypt/decrypt data
            val testData = "availability_test".toByteArray()
            val encrypted = encrypt(testData)
            val decrypted = decrypt(encrypted)
            testData.contentEquals(decrypted)
        } catch (e: Exception) {
            logger.error("Secure storage availability test failed", e)
            false
        }
    }

    /**
     * Encrypt data using AES-GCM
     */
    private fun encrypt(data: ByteArray): ByteArray {
        // Generate random IV
        val iv = ByteArray(ivLength)
        SecureRandom().nextBytes(iv)

        // Initialize cipher for encryption
        cipher.init(Cipher.ENCRYPT_MODE, secretKey, GCMParameterSpec(gcmTagLength * 8, iv))

        // Encrypt data
        val encryptedData = cipher.doFinal(data)

        // Combine IV + encrypted data
        return iv + encryptedData
    }

    /**
     * Decrypt data using AES-GCM
     */
    private fun decrypt(encryptedDataWithIv: ByteArray): ByteArray {
        // Extract IV and encrypted data
        val iv = encryptedDataWithIv.sliceArray(0 until ivLength)
        val encryptedData = encryptedDataWithIv.sliceArray(ivLength until encryptedDataWithIv.size)

        // Initialize cipher for decryption
        cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(gcmTagLength * 8, iv))

        // Decrypt data
        return cipher.doFinal(encryptedData)
    }
}

/**
 * JVM implementation of SecureStorageFactory
 */
actual class SecureStorageFactory {
    actual companion object {
        actual fun create(identifier: String): SecureStorage {
            return JvmSecureStorage.create(identifier)
        }

        actual fun isSupported(): Boolean {
            return JvmSecureStorage.isSupported()
        }
    }
}
