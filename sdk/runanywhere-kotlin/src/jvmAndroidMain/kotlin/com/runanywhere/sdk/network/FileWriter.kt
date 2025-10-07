package com.runanywhere.sdk.network

import java.io.File

/**
 * Shared file writing implementation for JVM and Android
 */
actual suspend fun writeFileBytes(path: String, data: ByteArray) {
    val file = File(path)
    file.parentFile?.mkdirs()
    file.writeBytes(data)
}
