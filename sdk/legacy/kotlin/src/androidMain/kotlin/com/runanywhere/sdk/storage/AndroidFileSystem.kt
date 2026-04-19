package com.runanywhere.sdk.storage

import android.content.Context

/**
 * Android implementation of FileSystem
 * Extends shared implementation and provides Android-specific directory paths
 */
internal class AndroidFileSystem(
    private val context: Context,
) : SharedFileSystem() {
    override fun getCacheDirectory(): String = context.cacheDir.absolutePath

    override fun getDataDirectory(): String = context.filesDir.absolutePath

    override fun getTempDirectory(): String = context.cacheDir.absolutePath
}

/**
 * Factory function to create FileSystem for Android
 */
actual fun createFileSystem(): FileSystem = AndroidFileSystem(AndroidPlatformContext.applicationContext)
