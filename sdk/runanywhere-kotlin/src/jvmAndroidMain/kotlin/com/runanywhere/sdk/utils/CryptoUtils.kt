package com.runanywhere.sdk.utils

import java.security.MessageDigest

/**
 * Shared cryptographic utilities for JVM and Android platforms
 */
fun calculateSHA256(data: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val hash = digest.digest(data)
    return hash.joinToString("") { "%02x".format(it) }
}
