package com.runanywhere.sdk.services

/**
 * Native implementation of MD5 calculation
 * This is a simplified implementation for native platforms
 * In production, you would use a proper crypto library
 */
actual fun calculateMD5(data: ByteArray): String {
    // Simple hash for native platforms - not cryptographically secure
    // For production, integrate with a proper native crypto library
    var hash = 0
    for (byte in data) {
        hash = ((hash shl 5) - hash) + byte.toInt()
        hash = hash and hash // Convert to 32-bit integer
    }

    // Convert to hex string format similar to MD5
    val result = StringBuilder()
    var tempHash = hash
    repeat(16) {
        val byte = (tempHash and 0xFF).toByte()
        result.append("%02x".format(byte))
        tempHash = tempHash shr 8
    }

    return result.toString()
}
