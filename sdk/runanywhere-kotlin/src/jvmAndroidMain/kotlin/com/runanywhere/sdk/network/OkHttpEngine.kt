package com.runanywhere.sdk.network

import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Shared OkHttp implementation for JVM and Android
 */
internal class OkHttpEngine : HttpClient {

    private var defaultHeaders = mutableMapOf<String, String>()
    private var timeoutMillis = 30_000L

    private val client: OkHttpClient
        get() = OkHttpClient.Builder()
            .connectTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
            .readTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
            .writeTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
            .build()

    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        val request = Request.Builder()
            .url(url)
            .apply {
                (defaultHeaders + headers).forEach { (key, value) ->
                    addHeader(key, value)
                }
            }
            .get()
            .build()

        return executeRequest(request)
    }

    override suspend fun post(
        url: String,
        body: ByteArray,
        headers: Map<String, String>
    ): HttpResponse {
        val requestBody = body.toRequestBody("application/octet-stream".toMediaType())
        val request = Request.Builder()
            .url(url)
            .apply {
                (defaultHeaders + headers).forEach { (key, value) ->
                    addHeader(key, value)
                }
            }
            .post(requestBody)
            .build()

        return executeRequest(request)
    }

    override suspend fun put(
        url: String,
        body: ByteArray,
        headers: Map<String, String>
    ): HttpResponse {
        val requestBody = body.toRequestBody("application/octet-stream".toMediaType())
        val request = Request.Builder()
            .url(url)
            .apply {
                (defaultHeaders + headers).forEach { (key, value) ->
                    addHeader(key, value)
                }
            }
            .put(requestBody)
            .build()

        return executeRequest(request)
    }

    override suspend fun delete(url: String, headers: Map<String, String>): HttpResponse {
        val request = Request.Builder()
            .url(url)
            .apply {
                (defaultHeaders + headers).forEach { (key, value) ->
                    addHeader(key, value)
                }
            }
            .delete()
            .build()

        return executeRequest(request)
    }

    override suspend fun download(
        url: String,
        headers: Map<String, String>,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?
    ): ByteArray {
        val response = get(url, headers)
        if (!response.isSuccessful) {
            throw IOException("Download failed with status: ${response.statusCode}")
        }
        return response.body
    }

    override suspend fun upload(
        url: String,
        data: ByteArray,
        headers: Map<String, String>,
        onProgress: ((bytesUploaded: Long, totalBytes: Long) -> Unit)?
    ): HttpResponse {
        return post(url, data, headers)
    }

    override fun setDefaultTimeout(timeoutMillis: Long) {
        this.timeoutMillis = timeoutMillis
    }

    override fun setDefaultHeaders(headers: Map<String, String>) {
        defaultHeaders = headers.toMutableMap()
    }

    private suspend fun executeRequest(request: Request): HttpResponse =
        suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)

            continuation.invokeOnCancellation {
                call.cancel()
            }

            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    try {
                        val body = response.body?.bytes() ?: ByteArray(0)
                        val headers = response.headers.toMultimap()

                        continuation.resume(
                            HttpResponse(
                                statusCode = response.code,
                                body = body,
                                headers = headers
                            )
                        )
                    } catch (e: Exception) {
                        continuation.resumeWithException(e)
                    } finally {
                        response.close()
                    }
                }
            })
        }
}

/**
 * Factory function to create HttpClient for JVM and Android
 */
actual fun createHttpClient(): HttpClient = OkHttpEngine()
