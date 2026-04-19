package com.runanywhere.sdk.platform

/**
 * Platform-specific storage information
 * Matches iOS platform-specific storage calculations
 *
 * Reference: iOS uses different APIs per platform (iOS: FileManager, macOS: URL.volumeAvailableCapacityKey)
 */
data class PlatformStorageInfo(
    val totalSpace: Long, // Total storage capacity in bytes
    val availableSpace: Long, // Available storage in bytes
    val usedSpace: Long, // Used storage in bytes
)

/**
 * Get platform-specific storage information
 * Matches iOS FileManager.default.volumeAvailableCapacity pattern
 *
 * Implementation varies by platform:
 * - Android: Uses StatFs
 * - JVM: Uses File.getTotalSpace/getUsableSpace
 */
expect suspend fun getPlatformStorageInfo(path: String): PlatformStorageInfo

/**
 * Get platform-specific base directory for RunAnywhere SDK
 * Matches iOS FileManager.default.urls(for: .applicationSupportDirectory)
 *
 * Implementation varies by platform:
 * - Android: Context.filesDir + "/runanywhere"
 * - JVM: User home + "/.runanywhere"
 */
expect fun getPlatformBaseDirectory(): String

/**
 * Get platform-specific temp directory
 * Matches iOS FileManager.default.temporaryDirectory
 *
 * Implementation varies by platform:
 * - Android: Context.cacheDir
 * - JVM: System.getProperty("java.io.tmpdir") + "/runanywhere"
 */
expect fun getPlatformTempDirectory(): String
