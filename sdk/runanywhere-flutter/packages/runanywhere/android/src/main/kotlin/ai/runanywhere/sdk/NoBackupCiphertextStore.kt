/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package ai.runanywhere.sdk

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.security.MessageDigest

/** Atomic ciphertext storage excluded from Android backup and device transfer. */
internal class NoBackupCiphertextStore(
    context: Context,
    directoryName: String,
) {
    private val directory = File(context.noBackupFilesDir, directoryName)

    init {
        require(directoryName.matches(SAFE_DIRECTORY_NAME)) {
            "Invalid secure-storage directory name"
        }
    }

    fun read(key: String): ByteArray? =
        synchronized(IO_LOCK) {
            val entry = entryFile(key)
            if (!entry.exists() && !backupFile(entry).exists()) return@synchronized null
            AtomicFile(entry).openRead().use { it.readBytes() }
        }

    fun write(
        key: String,
        value: ByteArray,
    ): Boolean =
        synchronized(IO_LOCK) {
            ensureDirectory()
            val atomicFile = AtomicFile(entryFile(key))
            var output: FileOutputStream? = null
            try {
                output = atomicFile.startWrite()
                output.write(value)
                // AtomicFile.finishWrite fsyncs and closes before returning, so
                // the synchronous FFI callback only acknowledges durable data.
                atomicFile.finishWrite(output)
                true
            } catch (exception: Exception) {
                atomicFile.failWrite(output)
                throw exception
            }
        }

    fun delete(key: String): Boolean =
        synchronized(IO_LOCK) {
            val entry = entryFile(key)
            AtomicFile(entry).delete()
            !entry.exists() && !backupFile(entry).exists() && !newFile(entry).exists()
        }

    private fun entryFile(key: String): File = File(directory, sha256(key))

    private fun ensureDirectory() {
        if ((!directory.exists() && !directory.mkdirs()) || !directory.isDirectory) {
            throw IOException("Unable to open secure-storage directory")
        }
    }

    private companion object {
        val SAFE_DIRECTORY_NAME = Regex("[A-Za-z0-9._-]+")
        val IO_LOCK = Any()
        val HEX = "0123456789abcdef".toCharArray()

        fun backupFile(entry: File): File = File(entry.path + ".bak")

        fun newFile(entry: File): File = File(entry.path + ".new")

        fun sha256(value: String): String {
            val digest =
                MessageDigest
                    .getInstance("SHA-256")
                    .digest(value.toByteArray(StandardCharsets.UTF_8))
            return buildString(digest.size * 2) {
                digest.forEach { byte ->
                    val unsigned = byte.toInt() and 0xff
                    append(HEX[unsigned ushr 4])
                    append(HEX[unsigned and 0x0f])
                }
            }
        }
    }
}
