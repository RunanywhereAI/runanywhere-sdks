package com.runanywhere.sdk.network

import com.runanywhere.sdk.foundation.SDKLogger

private val logger = SDKLogger("FileWriter")

/**
 * Native implementation of file writing
 * This is a placeholder - actual implementation would use platform-specific APIs
 */
actual suspend fun writeFileBytes(path: String, data: ByteArray) {
    // Native platforms would need platform-specific file I/O
    // This is a placeholder implementation
    logger.warning("Writing ${data.size} bytes to $path (not implemented on native)")
}
