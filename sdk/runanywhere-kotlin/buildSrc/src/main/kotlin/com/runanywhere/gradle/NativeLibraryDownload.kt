package com.runanywhere.gradle

import org.gradle.api.GradleException
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest

object NativeLibraryDownload {
    private const val CONNECT_TIMEOUT_MILLIS = 30_000
    private const val READ_TIMEOUT_MILLIS = 120_000

    fun downloadZipWithChecksum(
        zipUrl: String,
        destination: File,
    ) {
        destination.parentFile.mkdirs()
        val expectedSha256 = downloadText("$zipUrl.sha256").firstSha256Token()

        try {
            downloadToFile(zipUrl, destination)
            val actualSha256 = destination.sha256()
            if (!actualSha256.equals(expectedSha256, ignoreCase = true)) {
                throw GradleException(
                    "SHA256 mismatch for $zipUrl: expected $expectedSha256 but downloaded $actualSha256",
                )
            }
        } catch (e: Exception) {
            destination.delete()
            throw e
        }
    }

    private fun downloadToFile(
        url: String,
        destination: File,
    ) {
        val connection = openHttpConnection(url)
        try {
            connection.inputStream.use { input ->
                destination.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun downloadText(url: String): String {
        val connection = openHttpConnection(url)
        return try {
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
    }

    private fun openHttpConnection(url: String): HttpURLConnection {
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
        connection.readTimeout = READ_TIMEOUT_MILLIS
        connection.instanceFollowRedirects = true
        connection.requestMethod = "GET"

        val responseCode = connection.responseCode
        if (responseCode !in 200..299) {
            connection.disconnect()
            throw GradleException("Failed to download $url: HTTP $responseCode")
        }

        return connection
    }

    private fun String.firstSha256Token(): String {
        val token = trim().split(Regex("\\s+")).firstOrNull()
        if (token == null || !token.matches(Regex("[a-fA-F0-9]{64}"))) {
            throw GradleException("Invalid SHA256 checksum content")
        }
        return token.lowercase()
    }

    private fun File.sha256(): String {
        val digest = MessageDigest.getInstance("SHA-256")
        inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read == -1) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
