package com.runanywhere.sdk.platform

import android.os.Build
import android.os.StatFs
import android.os.Environment
import com.runanywhere.sdk.storage.AndroidPlatformContext

/**
 * Android implementation of platform-specific storage operations
 * Uses Android StatFs for storage calculations
 *
 * Reference: Matches iOS FileManager storage calculations but uses Android APIs
 */

actual suspend fun getPlatformStorageInfo(path: String): PlatformStorageInfo {
    val statFs = StatFs(path)

    val totalSpace = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
        statFs.totalBytes
    } else {
        @Suppress("DEPRECATION")
        statFs.blockCount.toLong() * statFs.blockSize.toLong()
    }

    val availableSpace = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
        statFs.availableBytes
    } else {
        @Suppress("DEPRECATION")
        statFs.availableBlocks.toLong() * statFs.blockSize.toLong()
    }

    val usedSpace = totalSpace - availableSpace

    return PlatformStorageInfo(
        totalSpace = totalSpace,
        availableSpace = availableSpace,
        usedSpace = usedSpace
    )
}

actual fun getPlatformBaseDirectory(): String {
    val context = AndroidPlatformContext.applicationContext

    // Match iOS pattern: app-specific directory for SDK files
    // iOS: .applicationSupportDirectory
    // Android: filesDir/runanywhere
    val baseDir = context.filesDir.resolve("runanywhere")
    if (!baseDir.exists()) {
        baseDir.mkdirs()
    }
    return baseDir.absolutePath
}

actual fun getPlatformTempDirectory(): String {
    val context = AndroidPlatformContext.applicationContext

    // Match iOS pattern: temporary directory
    // iOS: .temporaryDirectory
    // Android: cacheDir/runanywhere-temp
    val tempDir = context.cacheDir.resolve("runanywhere-temp")
    if (!tempDir.exists()) {
        tempDir.mkdirs()
    }
    return tempDir.absolutePath
}
