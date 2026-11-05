package com.runanywhere.gradle

import org.gradle.api.GradleException
import java.io.File
import java.net.HttpURLConnection
import java.net.URI

/**
 * HTTP download helper for [downloadJniLibs] tasks. Extracted from the root
 * build script so behavior (timeouts, retries, 4xx handling) is unit-testable.
 */
class NonRetryableDownloadException(message: String) : GradleException(message)

object NativeArchiveDownloader {
    fun downloadWithTimeouts(url: String, dest: File) {
        val maxAttempts = 3
        val deadlineMillis = 10 * 60_000L
        var lastFailure: Exception? = null
        for (attempt in 1..maxAttempts) {
            dest.delete()
            val connection = URI(url).toURL().openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 60_000
            connection.instanceFollowRedirects = true
            try {
                val code = connection.responseCode
                if (code in 400..499) throw NonRetryableDownloadException("HTTP $code for $url")
                if (code != 200) throw GradleException("HTTP $code for $url")
                val deadline = System.nanoTime() + deadlineMillis * 1_000_000L
                connection.inputStream.use { input ->
                    dest.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            if (System.nanoTime() > deadline) {
                                throw GradleException(
                                    "Download of $url exceeded ${deadlineMillis / 1000}s",
                                )
                            }
                            output.write(buffer, 0, read)
                        }
                    }
                }
                return
            } catch (e: NonRetryableDownloadException) {
                dest.delete()
                throw e
            } catch (e: Exception) {
                dest.delete()
                lastFailure = e
                if (attempt < maxAttempts) Thread.sleep(2_000L * attempt)
            } finally {
                connection.disconnect()
            }
        }
        throw GradleException("Download failed after $maxAttempts attempts: $url", lastFailure)
    }
}
