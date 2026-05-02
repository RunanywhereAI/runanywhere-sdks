package com.runanywhere.runanywhereai

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownload
import timber.log.Timber
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

class HttpUrlConnectionDownloadProvider : CppBridgeDownload.DownloadProvider {

    override fun download(
        url: String,
        destinationPath: String,
        progressCallback: (downloadedBytes: Long, totalBytes: Long) -> Unit,
    ): Boolean {
        var current = url
        var hops = 0
        while (hops < MAX_REDIRECTS) {
            val conn = URL(current).openConnection() as HttpURLConnection
            conn.connectTimeout = CONNECT_TIMEOUT_MS
            conn.readTimeout = READ_TIMEOUT_MS
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("User-Agent", USER_AGENT)
            conn.setRequestProperty("Accept", "*/*")

            val code = conn.responseCode
            if (code in 300..399) {
                val location = conn.getHeaderField("Location")
                conn.disconnect()
                if (location.isNullOrBlank()) {
                    Timber.e("Redirect %d with no Location header for %s", code, current)
                    return false
                }
                current = if (location.startsWith("http")) location else URL(URL(current), location).toString()
                hops++
                continue
            }
            if (code !in 200..299) {
                Timber.e("HTTP %d for %s", code, current)
                conn.disconnect()
                return false
            }

            val total = conn.contentLengthLong.coerceAtLeast(-1L)
            val dest = File(destinationPath)
            dest.parentFile?.mkdirs()
            try {
                conn.inputStream.use { input ->
                    FileOutputStream(dest).use { output ->
                        val buf = ByteArray(BUFFER_BYTES)
                        var written = 0L
                        var lastEmit = 0L
                        while (true) {
                            val n = input.read(buf)
                            if (n < 0) break
                            output.write(buf, 0, n)
                            written += n
                            val now = System.currentTimeMillis()
                            if (now - lastEmit >= PROGRESS_INTERVAL_MS) {
                                lastEmit = now
                                progressCallback(written, total)
                            }
                        }
                        progressCallback(written, if (total > 0) total else written)
                    }
                }
                return true
            } catch (t: Throwable) {
                Timber.e(t, "Download exception for %s", current)
                runCatching { if (dest.exists()) dest.delete() }
                return false
            } finally {
                conn.disconnect()
            }
        }
        Timber.e("Too many redirects for %s", url)
        return false
    }

    override fun supportsResume(url: String): Boolean = false

    private companion object {
        const val MAX_REDIRECTS = 10
        const val CONNECT_TIMEOUT_MS = 30_000
        const val READ_TIMEOUT_MS = 120_000
        const val BUFFER_BYTES = 64 * 1024
        const val PROGRESS_INTERVAL_MS = 200L
        const val USER_AGENT = "RunAnywhere-Android-Example/1.0"
    }
}
