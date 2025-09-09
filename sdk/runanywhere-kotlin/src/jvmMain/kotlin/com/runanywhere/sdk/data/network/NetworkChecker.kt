package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.network.NetworkChecker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.InetAddress

/**
 * JVM implementation of platform-specific network checker
 */
actual fun createPlatformNetworkChecker(): NetworkChecker? = JvmNetworkChecker()

/**
 * JVM network checker implementation using Java networking APIs
 */
class JvmNetworkChecker : NetworkChecker {
    override suspend fun isNetworkAvailable(): Boolean = withContext(Dispatchers.IO) {
        try {
            // Try to resolve a reliable host
            val address = InetAddress.getByName("8.8.8.8")
            address.isReachable(3000) // 3 second timeout
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun getNetworkType(): String = withContext(Dispatchers.IO) {
        if (isNetworkAvailable()) {
            "Desktop" // JVM is typically running on desktop
        } else {
            "None"
        }
    }
}
