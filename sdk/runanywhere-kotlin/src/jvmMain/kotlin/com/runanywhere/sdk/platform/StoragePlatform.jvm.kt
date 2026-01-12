package com.runanywhere.sdk.platform

import java.io.File

/**
 * JVM implementation of platform-specific storage operations
 * Uses Java File API for storage calculations
 *
 * Reference: Matches iOS FileManager storage calculations but uses JVM APIs
 */

actual suspend fun getPlatformStorageInfo(path: String): PlatformStorageInfo {
    val file = File(path)

    val totalSpace = file.totalSpace
    val availableSpace = file.usableSpace
    val usedSpace = totalSpace - availableSpace

    return PlatformStorageInfo(
        totalSpace = totalSpace,
        availableSpace = availableSpace,
        usedSpace = usedSpace,
    )
}

actual fun getPlatformBaseDirectory(): String {
    // Match iOS pattern: app-specific directory for SDK files
    // iOS: .applicationSupportDirectory
    // JVM: ~/.runanywhere
    val userHome = System.getProperty("user.home")
    val baseDir = File(userHome, ".runanywhere")
    if (!baseDir.exists()) {
        baseDir.mkdirs()
    }
    return baseDir.absolutePath
}

actual fun getPlatformTempDirectory(): String {
    // Match iOS pattern: temporary directory
    // iOS: .temporaryDirectory
    // JVM: temp directory/runanywhere-temp
    val systemTemp = System.getProperty("java.io.tmpdir")
    val tempDir = File(systemTemp, "runanywhere-temp")
    if (!tempDir.exists()) {
        tempDir.mkdirs()
    }
    return tempDir.absolutePath
}
