package com.runanywhere.sdk.services

import java.security.MessageDigest

/**
 * Android implementation of MD5 calculation
 * Uses the same Java MessageDigest as JVM
 */
actual fun calculateMD5(data: ByteArray): String {
    val digest = MessageDigest.getInstance("MD5")
    val hashBytes = digest.digest(data)
    return hashBytes.joinToString("") { "%02x".format(it) }
}
