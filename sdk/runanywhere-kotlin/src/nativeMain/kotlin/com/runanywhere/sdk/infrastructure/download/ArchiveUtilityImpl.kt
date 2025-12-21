package com.runanywhere.sdk.infrastructure.download

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.cinterop.*
import platform.Foundation.*
import platform.posix.*

private val logger = SDKLogger("ArchiveUtilityImpl")

/**
 * Extract tar.bz2 archive using native Process/shell commands
 * On Apple platforms, we use the built-in tar command which supports bz2
 */
@OptIn(ExperimentalForeignApi::class)
internal actual suspend fun extractTarBz2Impl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?
) {
    logger.info("Extracting tar.bz2 using native tar command")
    progressHandler?.invoke(0.1)

    // Ensure destination exists
    createDirectory(destinationPath)

    // Use tar command with bunzip2 decompression
    val result = executeShellCommand("tar", listOf("-xjf", sourcePath, "-C", destinationPath))

    if (result != 0) {
        throw Exception("tar extraction failed with exit code: $result")
    }

    progressHandler?.invoke(1.0)
    logger.info("tar.bz2 extraction completed")
}

/**
 * Extract tar.gz archive using native Process/shell commands
 * On Apple platforms, we use the built-in tar command which supports gzip
 */
@OptIn(ExperimentalForeignApi::class)
internal actual suspend fun extractTarGzImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?
) {
    logger.info("Extracting tar.gz using native tar command")
    progressHandler?.invoke(0.1)

    // Ensure destination exists
    createDirectory(destinationPath)

    // Use tar command with gzip decompression
    val result = executeShellCommand("tar", listOf("-xzf", sourcePath, "-C", destinationPath))

    if (result != 0) {
        throw Exception("tar extraction failed with exit code: $result")
    }

    progressHandler?.invoke(1.0)
    logger.info("tar.gz extraction completed")
}

/**
 * Extract tar.xz archive using native Process/shell commands
 * On Apple platforms, we use the built-in tar command which supports xz
 */
@OptIn(ExperimentalForeignApi::class)
internal actual suspend fun extractTarXzImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?
) {
    logger.info("Extracting tar.xz using native tar command")
    progressHandler?.invoke(0.1)

    // Ensure destination exists
    createDirectory(destinationPath)

    // Use tar command with xz decompression
    val result = executeShellCommand("tar", listOf("-xJf", sourcePath, "-C", destinationPath))

    if (result != 0) {
        throw Exception("tar extraction failed with exit code: $result")
    }

    progressHandler?.invoke(1.0)
    logger.info("tar.xz extraction completed")
}

/**
 * Extract zip archive using native unzip or ditto commands
 * On Apple platforms, we prefer ditto for preserving resource forks
 */
@OptIn(ExperimentalForeignApi::class)
internal actual suspend fun extractZipImpl(
    sourcePath: String,
    destinationPath: String,
    progressHandler: ((Double) -> Unit)?
) {
    logger.info("Extracting zip using native command")
    progressHandler?.invoke(0.1)

    // Ensure destination exists
    createDirectory(destinationPath)

    // Try ditto first (preserves macOS-specific attributes)
    var result = executeShellCommand("ditto", listOf("-xk", sourcePath, destinationPath))

    if (result != 0) {
        // Fallback to unzip
        logger.debug("ditto failed, falling back to unzip")
        result = executeShellCommand("unzip", listOf("-o", "-q", sourcePath, "-d", destinationPath))
    }

    if (result != 0) {
        throw Exception("zip extraction failed with exit code: $result")
    }

    progressHandler?.invoke(1.0)
    logger.info("zip extraction completed")
}

/**
 * Create directory if it doesn't exist
 */
@OptIn(ExperimentalForeignApi::class)
private fun createDirectory(path: String) {
    val fileManager = NSFileManager.defaultManager
    val nsPath = path as NSString

    @Suppress("UNCHECKED_CAST")
    val exists = fileManager.fileExistsAtPath(nsPath as String)
    if (!exists) {
        fileManager.createDirectoryAtPath(
            path,
            withIntermediateDirectories = true,
            attributes = null,
            error = null
        )
    }
}

/**
 * Execute a shell command and return the exit code
 */
@OptIn(ExperimentalForeignApi::class)
private fun executeShellCommand(command: String, args: List<String>): Int {
    val task = NSTask()

    // Find the executable path
    val executablePath = when (command) {
        "tar" -> "/usr/bin/tar"
        "ditto" -> "/usr/bin/ditto"
        "unzip" -> "/usr/bin/unzip"
        else -> "/usr/bin/$command"
    }

    task.setLaunchPath(executablePath)

    @Suppress("UNCHECKED_CAST")
    task.setArguments(args as List<Any>)

    try {
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus
    } catch (e: Exception) {
        logger.error("Shell command failed: ${e.message}")
        return -1
    }
}
