package com.runanywhere.sdk.services

import java.security.MessageDigest

/**
 * Shared JVM/Android implementation of MD5 calculation
 */
actual fun calculateMD5(data: ByteArray): String {
    val digest = MessageDigest.getInstance("MD5")
    val hashBytes = digest.digest(data)
    return hashBytes.joinToString("") { "%02x".format(it) }
}
