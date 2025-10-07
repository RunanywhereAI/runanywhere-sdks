package com.runanywhere.sdk.storage

/**
 * JVM implementation of FileSystem using java.io.File
 * Extends shared implementation and provides JVM-specific directory paths
 */
internal class JvmFileSystem : SharedFileSystem() {

    override fun getCacheDirectory(): String {
        return System.getProperty("java.io.tmpdir") ?: "/tmp"
    }

    override fun getDataDirectory(): String {
        return System.getProperty("user.home") + "/.runanywhere"
    }

    override fun getTempDirectory(): String {
        return System.getProperty("java.io.tmpdir") ?: "/tmp"
    }
}

/**
 * Factory function to create FileSystem for JVM
 */
actual fun createFileSystem(): FileSystem = JvmFileSystem()
