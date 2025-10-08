package com.runanywhere.sdk.models

import com.runanywhere.sdk.storage.FileSystem
import java.security.MessageDigest

/**
 * JVM implementation of platform-specific checksum calculation
 */
actual suspend fun calculatePlatformChecksum(filePath: String, algorithm: String, fileSystem: FileSystem): String {
    val fileData = fileSystem.readBytes(filePath)
    val digest = MessageDigest.getInstance(algorithm)
    val hashBytes = digest.digest(fileData)
    return hashBytes.joinToString("") { "%02x".format(it) }
}