package com.runanywhere.sdk.infrastructure.modelmanagement.services

import kotlinx.cinterop.*
import platform.Foundation.*
import platform.posix.*

/**
 * Get current time in milliseconds (Native/Apple implementation)
 */
@OptIn(ExperimentalForeignApi::class)
internal actual fun currentTimeMillis(): Long {
    return (NSDate().timeIntervalSince1970 * 1000).toLong()
}

/**
 * Create a directory if it doesn't exist (Native/Apple implementation)
 */
@OptIn(ExperimentalForeignApi::class)
internal actual fun createDirectoryIfNeeded(path: String) {
    val fileManager = NSFileManager.defaultManager

    @Suppress("UNCHECKED_CAST")
    val exists = fileManager.fileExistsAtPath(path)
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
 * List contents of a directory (Native/Apple implementation)
 */
@OptIn(ExperimentalForeignApi::class)
internal actual fun listDirectoryContents(path: String): List<String>? {
    val fileManager = NSFileManager.defaultManager

    var isDirectory: Boolean = false
    memScoped {
        val isDirPtr = alloc<platform.objc.ObjCObjectVar<Any?>>()
        fileManager.fileExistsAtPath(path, isDirectory = null)
    }

    @Suppress("UNCHECKED_CAST")
    val contents = fileManager.contentsOfDirectoryAtPath(path, error = null) as? List<String>
    return contents
}

/**
 * Check if a path is a directory (Native/Apple implementation)
 */
@OptIn(ExperimentalForeignApi::class)
internal actual fun isDirectoryPath(path: String): Boolean {
    val fileManager = NSFileManager.defaultManager

    memScoped {
        val isDirPtr = alloc<platform.objc.ObjCObjectVar<Any?>>()
        val exists = fileManager.fileExistsAtPath(path, isDirectory = null)
        if (!exists) return false

        // Check if it's a directory using attributes
        @Suppress("UNCHECKED_CAST")
        val attrs = fileManager.attributesOfItemAtPath(path, error = null) as? Map<Any?, Any?>
        val fileType = attrs?.get(NSFileType)
        return fileType == NSFileTypeDirectory
    }
}

/**
 * Calculate total size and file count for a directory (Native/Apple implementation)
 */
@OptIn(ExperimentalForeignApi::class)
internal actual fun calculateDirectorySize(directory: String): Pair<Long, Int> {
    val fileManager = NSFileManager.defaultManager

    var totalSize = 0L
    var fileCount = 0

    val directoryURL = NSURL.fileURLWithPath(directory)

    @Suppress("UNCHECKED_CAST")
    val enumerator = fileManager.enumeratorAtURL(
        directoryURL,
        includingPropertiesForKeys = listOf(NSURLFileSizeKey, NSURLIsRegularFileKey) as List<Any>,
        options = 0u,
        errorHandler = null
    )

    if (enumerator != null) {
        while (true) {
            val fileURL = enumerator.nextObject() as? NSURL ?: break

            memScoped {
                val sizePtr = alloc<platform.objc.ObjCObjectVar<Any?>>()
                val isFilePtr = alloc<platform.objc.ObjCObjectVar<Any?>>()

                @Suppress("UNCHECKED_CAST")
                fileURL.getResourceValue(sizePtr.ptr as kotlinx.cinterop.CPointer<platform.objc.ObjCObjectVar<Any?>>, forKey = NSURLFileSizeKey, error = null)
                @Suppress("UNCHECKED_CAST")
                fileURL.getResourceValue(isFilePtr.ptr as kotlinx.cinterop.CPointer<platform.objc.ObjCObjectVar<Any?>>, forKey = NSURLIsRegularFileKey, error = null)

                val isFile = (isFilePtr.value as? NSNumber)?.boolValue ?: false
                if (isFile) {
                    val size = (sizePtr.value as? NSNumber)?.longLongValue ?: 0L
                    totalSize += size
                    fileCount++
                }
            }
        }
    }

    return Pair(totalSize, fileCount)
}
