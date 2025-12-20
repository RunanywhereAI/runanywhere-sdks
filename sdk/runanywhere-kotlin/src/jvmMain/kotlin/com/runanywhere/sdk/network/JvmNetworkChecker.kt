package com.runanywhere.sdk.network

import java.net.InetAddress

/**
 * JVM implementation of NetworkChecker
 */
class JvmNetworkChecker : NetworkChecker {
    override suspend fun isNetworkAvailable(): Boolean =
        try {
            val address = InetAddress.getByName("8.8.8.8")
            address.isReachable(3000)
        } catch (e: Exception) {
            false
        }

    override suspend fun getNetworkType(): String {
        // JVM doesn't have direct access to network type
        // Return "unknown" or try to detect based on network interfaces
        return if (isNetworkAvailable()) "ethernet" else "none"
    }
}
