package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.network.NetworkChecker

/**
 * Create platform-specific network checker for JVM and Android
 */
actual fun createPlatformNetworkChecker(): NetworkChecker? {
    return JvmAndroidNetworkChecker()
}

/**
 * Network connectivity checker for JVM and Android platforms
 */
internal class JvmAndroidNetworkChecker : NetworkChecker {

    override suspend fun isNetworkAvailable(): Boolean {
        return try {
            // Simple connectivity test using Java's built-in networking
            val url = java.net.URL("https://www.google.com")
            val connection = url.openConnection() as java.net.HttpURLConnection
            connection.requestMethod = "HEAD"
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            connection.connect()

            val responseCode = connection.responseCode
            connection.disconnect()

            responseCode == 200
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun getNetworkType(): String {
        // For JVM and Android, we can't easily determine network type
        // This would require platform-specific implementations
        return if (isNetworkAvailable()) "wifi" else "none"
    }
}
