package com.runanywhere.sdk.network

/**
 * Native implementation of file writing
 * This is a placeholder - actual implementation would use platform-specific APIs
 */
actual suspend fun writeFileBytes(path: String, data: ByteArray) {
    // Native platforms would need platform-specific file I/O
    // This is a placeholder implementation
    println("Writing ${data.size} bytes to $path (not implemented on native)")
}
