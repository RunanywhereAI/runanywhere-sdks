package com.runanywhere.sdk.infrastructure.filemanagement.utilities

import java.io.File

/**
 * Centralized utilities for file operations across the SDK.
 * Provides a single source of truth for all file system interactions.
 *
 * Mirrors Swift's `FileOperationsUtilities` in
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/FileManagement/Utilities/FileOperationsUtilities.swift`.
 */
public object FileOperationsUtilities {

    // MARK: - File Existence

    /**
     * Check if a file or directory exists and get whether it's a directory.
     *
     * @param path The filesystem path to check.
     * @return `Pair<exists, isDirectory>` — `exists` is true if the path exists,
     *         `isDirectory` is true when the path exists and points to a directory.
     */
    public fun existsWithType(path: String): Pair<Boolean, Boolean> {
        val file = File(path)
        val exists = file.exists()
        val isDirectory = exists && file.isDirectory
        return exists to isDirectory
    }

    // MARK: - File Attributes

    /**
     * Get the size of a regular file in bytes.
     *
     * @param path The filesystem path of the file.
     * @return File size in bytes, or `null` when the path does not exist or is not a regular file.
     */
    public fun fileSize(path: String): Long? {
        val file = File(path)
        return if (file.exists() && file.isFile) file.length() else null
    }
}
