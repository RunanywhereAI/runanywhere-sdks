package com.runanywhere.sdk.platform

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.security.MessageDigest

/**
 * JVM implementation of checksum calculation.
 * ONLY file I/O is here - business logic stays in commonMain.
 */

actual suspend fun calculateSHA256(filePath: String): String {
    return withContext(Dispatchers.IO) {
        calculateChecksumFromFile(filePath, "SHA-256")
    }
}

actual suspend fun calculateMD5(filePath: String): String {
    return withContext(Dispatchers.IO) {
        calculateChecksumFromFile(filePath, "MD5")
    }
}

actual fun calculateSHA256Bytes(data: ByteArray): String {
    return calculateChecksumFromBytes(data, "SHA-256")
}

actual fun calculateMD5Bytes(data: ByteArray): String {
    return calculateChecksumFromBytes(data, "MD5")
}

/**
 * Shared implementation for file-based checksum calculation.
 * Platform-specific: Uses java.io.File for file I/O.
 */
private fun calculateChecksumFromFile(filePath: String, algorithm: String): String {
    val file = File(filePath)
    if (!file.exists()) {
        throw IllegalArgumentException("File does not exist: $filePath")
    }

    val digest = MessageDigest.getInstance(algorithm)

    file.inputStream().use { input ->
        val buffer = ByteArray(8192) // 8KB buffer
        var bytesRead: Int

        while (input.read(buffer).also { bytesRead = it } != -1) {
            digest.update(buffer, 0, bytesRead)
        }
    }

    // Convert to hex string (lowercase to match Swift)
    return digest.digest().joinToString("") { "%02x".format(it) }
}

/**
 * Shared implementation for byte array checksum calculation.
 * Platform-specific: Uses java.security.MessageDigest.
 */
private fun calculateChecksumFromBytes(data: ByteArray, algorithm: String): String {
    val digest = MessageDigest.getInstance(algorithm)
    digest.update(data)

    // Convert to hex string (lowercase to match Swift)
    return digest.digest().joinToString("") { "%02x".format(it) }
}
