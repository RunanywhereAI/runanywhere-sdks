package com.runanywhere.sdk.utils

import com.runanywhere.sdk.network.SecureStorage
import java.io.File
import java.net.InetAddress
import java.util.*
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec
import java.security.KeyStore
import java.util.prefs.Preferences

/**
 * JVM implementation of platform utilities
 */
actual object PlatformUtils {

    private val prefs = Preferences.userNodeForPackage(PlatformUtils::class.java)
    private const val DEVICE_ID_KEY = "com.runanywhere.sdk.deviceId"

    actual fun getDeviceId(): String {
        // Check if we already have a stored device ID
        var deviceId = prefs.get(DEVICE_ID_KEY, null)

        if (deviceId == null) {
            // Generate a new UUID and store it
            deviceId = UUID.randomUUID().toString()
            prefs.put(DEVICE_ID_KEY, deviceId)
            prefs.flush()
        }

        return deviceId
    }

    actual fun getPlatformName(): String {
        return "jvm"
    }

    actual fun getDeviceInfo(): Map<String, String> {
        return mapOf(
            "platform" to getPlatformName(),
            "os_name" to System.getProperty("os.name", "Unknown"),
            "os_version" to getOSVersion(),
            "os_arch" to System.getProperty("os.arch", "Unknown"),
            "java_version" to System.getProperty("java.version", "Unknown"),
            "java_vendor" to System.getProperty("java.vendor", "Unknown"),
            "user_country" to System.getProperty("user.country", "Unknown"),
            "user_language" to System.getProperty("user.language", "Unknown"),
            "hostname" to getHostName(),
            "device_model" to getDeviceModel()
        )
    }

    actual fun getOSVersion(): String {
        return System.getProperty("os.version", "Unknown")
    }

    actual fun getDeviceModel(): String {
        // For JVM, return the OS name and architecture
        val osName = System.getProperty("os.name", "Unknown")
        val osArch = System.getProperty("os.arch", "Unknown")
        return "$osName $osArch"
    }

    actual fun getAppVersion(): String? {
        // Try to get version from manifest or return null
        return try {
            PlatformUtils::class.java.`package`?.implementationVersion
        } catch (e: Exception) {
            null
        }
    }

    private fun getHostName(): String {
        return try {
            InetAddress.getLocalHost().hostName
        } catch (e: Exception) {
            "Unknown"
        }
    }
}

/**
 * JVM implementation of secure storage using Java Preferences with optional encryption
 */
actual class SecureStorageImpl : SecureStorage {

    private val prefs = Preferences.userNodeForPackage(SecureStorageImpl::class.java)
    private val encryptionKey: SecretKey by lazy { getOrCreateKey() }

    override fun store(key: String, value: String) {
        try {
            // For sensitive data, we should encrypt it
            val encrypted = if (key.contains("token", ignoreCase = true) ||
                               key.contains("key", ignoreCase = true)) {
                encrypt(value)
            } else {
                value
            }
            prefs.put(key, encrypted)
            prefs.flush()
        } catch (e: Exception) {
            // Fallback to plain storage if encryption fails
            prefs.put(key, value)
            prefs.flush()
        }
    }

    override fun retrieve(key: String): String? {
        val value = prefs.get(key, null) ?: return null

        return try {
            // Try to decrypt if it looks like encrypted data
            if (key.contains("token", ignoreCase = true) ||
                key.contains("key", ignoreCase = true)) {
                decrypt(value)
            } else {
                value
            }
        } catch (e: Exception) {
            // Return as-is if decryption fails (might be plain text)
            value
        }
    }

    override fun remove(key: String) {
        prefs.remove(key)
        prefs.flush()
    }

    override fun clear() {
        prefs.clear()
        prefs.flush()
    }

    private fun getOrCreateKey(): SecretKey {
        val keyAlias = "RunAnywhereSDKKey"

        // For JVM, we'll use a simple key stored in preferences
        // In production, consider using Java KeyStore for better security
        val keyString = prefs.get("encryption_key", null)

        return if (keyString != null) {
            // Restore existing key
            val keyBytes = Base64.getDecoder().decode(keyString)
            SecretKeySpec(keyBytes, "AES")
        } else {
            // Generate new key
            val keyGen = KeyGenerator.getInstance("AES")
            keyGen.init(256)
            val key = keyGen.generateKey()

            // Store the key
            val keyString = Base64.getEncoder().encodeToString(key.encoded)
            prefs.put("encryption_key", keyString)
            prefs.flush()

            key
        }
    }

    private fun encrypt(plainText: String): String {
        val cipher = Cipher.getInstance("AES")
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey)
        val encryptedBytes = cipher.doFinal(plainText.toByteArray())
        return Base64.getEncoder().encodeToString(encryptedBytes)
    }

    private fun decrypt(encryptedText: String): String {
        val cipher = Cipher.getInstance("AES")
        cipher.init(Cipher.DECRYPT_MODE, encryptionKey)
        val encryptedBytes = Base64.getDecoder().decode(encryptedText)
        val decryptedBytes = cipher.doFinal(encryptedBytes)
        return String(decryptedBytes)
    }
}
