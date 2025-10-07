package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.network.NetworkChecker

/**
 * Create platform-specific network checker for Native platforms
 */
actual fun createPlatformNetworkChecker(): NetworkChecker? {
    return NativeNetworkChecker()
}

/**
 * Network connectivity checker for Native platforms (Linux, macOS, Windows)
 */
internal class NativeNetworkChecker : NetworkChecker {

    override suspend fun isNetworkAvailable(): Boolean {
        return try {
            // For native platforms, we use a simple approach
            // In a real implementation, this could use platform-specific APIs
            true // Assume network is available for now
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun getNetworkType(): String {
        // For native platforms, determining network type requires platform-specific code
        return "unknown"
    }
}
