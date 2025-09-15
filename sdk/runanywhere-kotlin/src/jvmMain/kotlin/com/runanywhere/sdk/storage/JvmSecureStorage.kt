package com.runanywhere.sdk.storage

import java.io.File
import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.attribute.PosixFilePermission
import java.security.SecureRandom
import java.util.Base64
import java.util.Properties
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * JVM implementation of SecureStorage using encrypted properties file with PBKDF2 key derivation
 * Uses secure file permissions and proper key management for production use
 */
internal class JvmSecureStorage : SecureStorage {
    companion object {
        private const val ALGORITHM = "AES"
        private const val TRANSFORMATION = "AES/CBC/PKCS5Padding"
        private const val KEY_DERIVATION_ALGORITHM = "PBKDF2WithHmacSHA256"
        private const val PBKDF2_ITERATIONS = 100_000
        private const val KEY_LENGTH = 256
        private const val SALT_LENGTH = 32
        private const val IV_LENGTH = 16
    }

    private val secureDir = File(System.getProperty("user.home"), ".runanywhere/secure")
    private val storageFile = File(secureDir, "storage.properties")
    private val saltFile = File(secureDir, "salt.dat")
    private val properties = Properties()
    private val masterPassword: String by lazy { generateMasterPassword() }
    private val salt: ByteArray by lazy { getOrCreateSalt() }

    init {
        createSecureDirectory()
        loadProperties()
    }

    override suspend fun setSecureString(key: String, value: String) {
        val encrypted = encrypt(value)
        properties.setProperty(key, encrypted)
        saveProperties()
    }

    override suspend fun getSecureString(key: String): String? {
        val encrypted = properties.getProperty(key) ?: return null
        return try {
            decrypt(encrypted)
        } catch (e: Exception) {
            // Return null for corrupted data rather than throwing
            null
        }
    }

    override suspend fun removeSecure(key: String) {
        properties.remove(key)
        saveProperties()
    }

    override suspend fun containsSecure(key: String): Boolean {
        return properties.containsKey(key)
    }

    override suspend fun clearSecure() {
        properties.clear()
        saveProperties()
    }

    /**
     * Creates a secure directory with restricted permissions (700 - owner only)
     */
    private fun createSecureDirectory() {
        if (!secureDir.exists()) {
            secureDir.mkdirs()
        }

        // Set secure permissions (owner only read/write/execute)
        try {
            val path = Paths.get(secureDir.absolutePath)
            val permissions = setOf(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE,
                PosixFilePermission.OWNER_EXECUTE
            )
            Files.setPosixFilePermissions(path, permissions)
        } catch (e: UnsupportedOperationException) {
            // Windows doesn't support POSIX permissions, but the directory is still created
            // On Windows, we rely on NTFS permissions which are typically restrictive by default
        }
    }

    /**
     * Gets or generates a master password using system properties for consistency
     */
    private fun generateMasterPassword(): String {
        // Use a combination of system properties to derive a consistent master password
        val userName = System.getProperty("user.name") ?: "default"
        val userHome = System.getProperty("user.home") ?: "/tmp"
        val osName = System.getProperty("os.name") ?: "unknown"

        // Create a deterministic but unique password based on system properties
        return "$userName:$userHome:$osName:runanywhere-secure-storage"
    }

    /**
     * Gets or creates a cryptographically secure salt for PBKDF2
     */
    private fun getOrCreateSalt(): ByteArray {
        if (saltFile.exists()) {
            return saltFile.readBytes()
        }

        val salt = ByteArray(SALT_LENGTH)
        SecureRandom().nextBytes(salt)

        saltFile.writeBytes(salt)
        setSecureFilePermissions(saltFile)

        return salt
    }

    /**
     * Derives a secret key using PBKDF2 with the master password and salt
     */
    private fun deriveKey(): SecretKeySpec {
        val spec = PBEKeySpec(
            masterPassword.toCharArray(),
            salt,
            PBKDF2_ITERATIONS,
            KEY_LENGTH
        )

        val factory = SecretKeyFactory.getInstance(KEY_DERIVATION_ALGORITHM)
        val derivedKey = factory.generateSecret(spec)

        return SecretKeySpec(derivedKey.encoded, ALGORITHM)
    }

    /**
     * Sets secure file permissions (600 - owner read/write only)
     */
    private fun setSecureFilePermissions(file: File) {
        try {
            val path = Paths.get(file.absolutePath)
            val permissions = setOf(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE
            )
            Files.setPosixFilePermissions(path, permissions)
        } catch (e: UnsupportedOperationException) {
            // Windows doesn't support POSIX permissions
            // Set basic file permissions using Java's File API
            file.setReadable(true, true)  // owner only
            file.setWritable(true, true)  // owner only
            file.setExecutable(false)     // no execute needed
        }
    }

    /**
     * Encrypts a value using AES-CBC with a randomly generated IV
     * Returns Base64 encoded string with IV prepended
     */
    private fun encrypt(value: String): String {
        val key = deriveKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)

        // Generate a random IV for each encryption
        val iv = ByteArray(IV_LENGTH)
        SecureRandom().nextBytes(iv)
        val ivSpec = IvParameterSpec(iv)

        cipher.init(Cipher.ENCRYPT_MODE, key, ivSpec)
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))

        // Prepend IV to encrypted data
        val combined = iv + encrypted
        return Base64.getEncoder().encodeToString(combined)
    }

    /**
     * Decrypts a Base64 encoded string that contains IV + encrypted data
     */
    private fun decrypt(encrypted: String): String {
        val key = deriveKey()
        val cipher = Cipher.getInstance(TRANSFORMATION)

        val combined = Base64.getDecoder().decode(encrypted)

        // Extract IV from the beginning
        val iv = combined.sliceArray(0 until IV_LENGTH)
        val encryptedData = combined.sliceArray(IV_LENGTH until combined.size)

        val ivSpec = IvParameterSpec(iv)
        cipher.init(Cipher.DECRYPT_MODE, key, ivSpec)

        val decrypted = cipher.doFinal(encryptedData)
        return String(decrypted, Charsets.UTF_8)
    }

    private fun loadProperties() {
        if (storageFile.exists()) {
            storageFile.inputStream().use { properties.load(it) }
        }
    }

    private fun saveProperties() {
        if (!secureDir.exists()) {
            createSecureDirectory()
        }

        storageFile.outputStream().use {
            properties.store(it, "RunAnywhere Secure Storage")
        }

        // Ensure secure file permissions on the storage file
        setSecureFilePermissions(storageFile)
    }
}

/**
 * Factory function to create secure storage for JVM
 */
actual fun createSecureStorage(): SecureStorage = JvmSecureStorage()
