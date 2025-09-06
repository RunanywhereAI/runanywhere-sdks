package com.runanywhere.sdk.storage

import java.io.File
import java.util.Base64
import java.util.Properties
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec

/**
 * JVM implementation of SecureStorage using encrypted properties file
 * In production, consider using a proper key management system
 */
internal class JvmSecureStorage : SecureStorage {
    private val storageFile =
        File(System.getProperty("user.home"), ".runanywhere/secure.properties")
    private val keyFile = File(System.getProperty("user.home"), ".runanywhere/key.dat")
    private val properties = Properties()
    private val secretKey: SecretKey by lazy { getOrCreateKey() }

    init {
        loadProperties()
    }

    override suspend fun setSecureString(key: String, value: String) {
        val encrypted = encrypt(value)
        properties.setProperty(key, encrypted)
        saveProperties()
    }

    override suspend fun getSecureString(key: String): String? {
        val encrypted = properties.getProperty(key) ?: return null
        return decrypt(encrypted)
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

    private fun getOrCreateKey(): SecretKey {
        if (keyFile.exists()) {
            val keyBytes = keyFile.readBytes()
            return SecretKeySpec(keyBytes, "AES")
        }

        val keyGen = KeyGenerator.getInstance("AES")
        keyGen.init(256)
        val key = keyGen.generateKey()

        keyFile.parentFile?.mkdirs()
        keyFile.writeBytes(key.encoded)

        return key
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val encrypted = cipher.doFinal(value.toByteArray())
        return Base64.getEncoder().encodeToString(encrypted)
    }

    private fun decrypt(encrypted: String): String {
        val cipher = Cipher.getInstance("AES")
        cipher.init(Cipher.DECRYPT_MODE, secretKey)
        val decoded = Base64.getDecoder().decode(encrypted)
        val decrypted = cipher.doFinal(decoded)
        return String(decrypted)
    }

    private fun loadProperties() {
        if (storageFile.exists()) {
            storageFile.inputStream().use { properties.load(it) }
        }
    }

    private fun saveProperties() {
        storageFile.parentFile?.mkdirs()
        storageFile.outputStream().use {
            properties.store(it, "RunAnywhere Secure Storage")
        }
    }
}

/**
 * Factory function to create secure storage for JVM
 */
actual fun createSecureStorage(): SecureStorage = JvmSecureStorage()
