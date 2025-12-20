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
    override suspend fun isNetworkAvailable(): Boolean =
        withContext(Dispatchers.IO) {
            try {
                // Try multiple methods to detect network connectivity
                // Method 1: Check if we can get any network interfaces
                val networkInterfaces = java.net.NetworkInterface.getNetworkInterfaces()
                while (networkInterfaces.hasMoreElements()) {
                    val networkInterface = networkInterfaces.nextElement()
                    if (networkInterface.isUp && !networkInterface.isLoopback) {
                        // Found at least one active non-loopback interface
                        return@withContext true
                    }
                }

                // Method 2: Try to resolve a hostname (fallback)
                try {
                    InetAddress.getByName("www.google.com")
                    true
                } catch (e: Exception) {
                    // Method 3: Try to connect to common DNS servers
                    try {
                        val socket = java.net.Socket()
                        val socketAddress = java.net.InetSocketAddress("8.8.8.8", 53)
                        socket.connect(socketAddress, 2000) // 2 second timeout
                        socket.close()
                        true
                    } catch (e: Exception) {
                        false
                    }
                }
            } catch (e: Exception) {
                // If all checks fail, assume network is available
                // This prevents false negatives that block SDK functionality
                true
            }
        }

    override suspend fun getNetworkType(): String =
        withContext(Dispatchers.IO) {
            if (isNetworkAvailable()) {
                "Desktop" // JVM is typically running on desktop
            } else {
                "None"
            }
        }
}
