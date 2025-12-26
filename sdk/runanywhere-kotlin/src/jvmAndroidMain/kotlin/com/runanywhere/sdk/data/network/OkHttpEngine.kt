package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Cache
import okhttp3.Call
import okhttp3.Callback
import okhttp3.CertificatePinner
import okhttp3.ConnectionPool
import okhttp3.ConnectionSpec
import okhttp3.Credentials
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.TlsVersion
import okhttp3.logging.HttpLoggingInterceptor
import okio.Buffer
import okio.BufferedSink
import okio.ForwardingSink
import okio.Sink
import okio.buffer
import java.io.File
import java.io.IOException
import java.net.Proxy
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Enhanced OkHttp implementation for JVM and Android with comprehensive configuration support
 */
internal class OkHttpEngine(
    private val config: NetworkConfiguration = NetworkConfiguration.production(),
) : HttpClient {
    private val logger = SDKLogger("OkHttpEngine")
    private var defaultHeaders = config.customHeaders.toMutableMap()

    // Build the configured OkHttpClient
    private val client: OkHttpClient by lazy { buildOkHttpClient() }

    /**
     * Build OkHttpClient with full configuration support
     */
    private fun buildOkHttpClient(): OkHttpClient {
        val builder = OkHttpClient.Builder()

        // Timeout configuration
        builder.connectTimeout(config.connectTimeoutMs, TimeUnit.MILLISECONDS)
        builder.readTimeout(config.readTimeoutMs, TimeUnit.MILLISECONDS)
        builder.writeTimeout(config.writeTimeoutMs, TimeUnit.MILLISECONDS)
        builder.callTimeout(config.callTimeoutMs, TimeUnit.MILLISECONDS)

        // Connection pool configuration
        val connectionPool =
            ConnectionPool(
                maxIdleConnections = config.maxIdleConnections,
                keepAliveDuration = config.keepAliveDurationMs,
                timeUnit = TimeUnit.MILLISECONDS,
            )
        builder.connectionPool(connectionPool)

        // Protocol configuration
        val protocols =
            mutableListOf<Protocol>().apply {
                if (config.enableHttp2) add(Protocol.HTTP_2)
                add(Protocol.HTTP_1_1)
            }
        builder.protocols(protocols)

        // Redirect configuration
        builder.followRedirects(config.followRedirects)
        builder.followSslRedirects(config.followRedirects)

        // Cache configuration
        if (config.enableResponseCaching && config.cacheDirectory != null) {
            try {
                val cacheDir = File(config.cacheDirectory)
                if (!cacheDir.exists()) cacheDir.mkdirs()
                val cache = Cache(cacheDir, config.cacheSizeBytes)
                builder.cache(cache)
            } catch (e: Exception) {
                logger.warn("Failed to setup cache: ${e.message}")
            }
        }

        // Proxy configuration
        config.proxyConfig?.let { proxyConfig ->
            when (proxyConfig) {
                is ProxyConfig.Http -> {
                    val proxy = Proxy(Proxy.Type.HTTP, java.net.InetSocketAddress(proxyConfig.host, proxyConfig.port))
                    builder.proxy(proxy)
                    if (proxyConfig.username != null && proxyConfig.password != null) {
                        builder.proxyAuthenticator { _, response ->
                            val credential = Credentials.basic(proxyConfig.username, proxyConfig.password)
                            response.request
                                .newBuilder()
                                .header("Proxy-Authorization", credential)
                                .build()
                        }
                    }
                }
                is ProxyConfig.Socks -> {
                    val proxy = Proxy(Proxy.Type.SOCKS, java.net.InetSocketAddress(proxyConfig.host, proxyConfig.port))
                    builder.proxy(proxy)
                }
                is ProxyConfig.Direct -> {
                    builder.proxy(Proxy.NO_PROXY)
                }
            }
        }

        // SSL/TLS configuration
        configureTls(builder)

        // Logging interceptor
        if (config.enableLogging) {
            val loggingLevel =
                when (config.logLevel) {
                    NetworkLogLevel.NONE -> HttpLoggingInterceptor.Level.NONE
                    NetworkLogLevel.BASIC -> HttpLoggingInterceptor.Level.BASIC
                    NetworkLogLevel.HEADERS -> HttpLoggingInterceptor.Level.HEADERS
                    NetworkLogLevel.BODY -> HttpLoggingInterceptor.Level.BODY
                    NetworkLogLevel.INFO -> HttpLoggingInterceptor.Level.HEADERS
                    NetworkLogLevel.DEBUG -> HttpLoggingInterceptor.Level.BODY
                }

            val loggingInterceptor =
                HttpLoggingInterceptor { message ->
                    logger.debug(message)
                }.apply {
                    level = loggingLevel
                    if (config.logBodySizeLimit > 0) {
                        setLevel(loggingLevel)
                    }
                }
            builder.addNetworkInterceptor(loggingInterceptor)
        }

        // User-Agent interceptor
        builder.addInterceptor { chain ->
            val request =
                chain
                    .request()
                    .newBuilder()
                    .header("User-Agent", config.userAgent)
                    .build()
            chain.proceed(request)
        }

        return builder.build()
    }

    /**
     * Configure SSL/TLS settings including certificate pinning
     */
    private fun configureTls(builder: OkHttpClient.Builder) {
        try {
            // Configure TLS versions
            val connectionSpec =
                ConnectionSpec
                    .Builder(ConnectionSpec.MODERN_TLS)
                    .tlsVersions(
                        *config.enableTlsVersions
                            .map {
                                when (it) {
                                    "TLSv1.2" -> TlsVersion.TLS_1_2
                                    "TLSv1.3" -> TlsVersion.TLS_1_3
                                    else -> TlsVersion.TLS_1_2
                                }
                            }.toTypedArray(),
                    ).build()

            builder.connectionSpecs(listOf(connectionSpec, ConnectionSpec.CLEARTEXT))

            // Hostname verification
            if (!config.hostnameVerification) {
                builder.hostnameVerifier { _, _ -> true }
            }

            // Certificate pinning
            config.certificatePinning?.let { pinningConfig ->
                val certificatePinner =
                    CertificatePinner
                        .Builder()
                        .apply {
                            pinningConfig.pins.forEach { (hostname, pins) ->
                                pins.forEach { pin ->
                                    add(hostname, "sha256/$pin")
                                }
                            }
                        }.build()
                builder.certificatePinner(certificatePinner)
            }
        } catch (e: Exception) {
            logger.warn("Failed to configure TLS: ${e.message}")
        }
    }

    override suspend fun get(
        url: String,
        headers: Map<String, String>,
    ): HttpResponse {
        val request =
            Request
                .Builder()
                .url(url)
                .apply {
                    (defaultHeaders + headers).forEach { (key, value) ->
                        addHeader(key, value)
                    }
                }.get()
                .build()

        return executeRequest(request)
    }

    override suspend fun post(
        url: String,
        body: ByteArray,
        headers: Map<String, String>,
    ): HttpResponse = postWithProgress(url, body, headers, null)

    /**
     * POST request with progress tracking
     */
    private suspend fun postWithProgress(
        url: String,
        body: ByteArray,
        headers: Map<String, String>,
        onProgress: ((bytesUploaded: Long, totalBytes: Long) -> Unit)?,
    ): HttpResponse {
        val contentType = headers["Content-Type"]?.toMediaType() ?: "application/octet-stream".toMediaType()

        val requestBody =
            if (onProgress != null) {
                ProgressRequestBody(body.toRequestBody(contentType), onProgress)
            } else {
                body.toRequestBody(contentType)
            }

        val request =
            Request
                .Builder()
                .url(url)
                .apply {
                    (defaultHeaders + headers).forEach { (key, value) ->
                        addHeader(key, value)
                    }
                }.post(requestBody)
                .build()

        return executeRequest(request)
    }

    override suspend fun put(
        url: String,
        body: ByteArray,
        headers: Map<String, String>,
    ): HttpResponse {
        val contentType = headers["Content-Type"]?.toMediaType() ?: "application/octet-stream".toMediaType()
        val requestBody = body.toRequestBody(contentType)
        val request =
            Request
                .Builder()
                .url(url)
                .apply {
                    (defaultHeaders + headers).forEach { (key, value) ->
                        addHeader(key, value)
                    }
                }.put(requestBody)
                .build()

        return executeRequest(request)
    }

    override suspend fun delete(
        url: String,
        headers: Map<String, String>,
    ): HttpResponse {
        val request =
            Request
                .Builder()
                .url(url)
                .apply {
                    (defaultHeaders + headers).forEach { (key, value) ->
                        addHeader(key, value)
                    }
                }.delete()
                .build()

        return executeRequest(request)
    }

    override suspend fun download(
        url: String,
        headers: Map<String, String>,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?,
    ): ByteArray {
        val request =
            Request
                .Builder()
                .url(url)
                .apply {
                    (defaultHeaders + headers).forEach { (key, value) ->
                        addHeader(key, value)
                    }
                }.get()
                .build()

        return suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)

            continuation.invokeOnCancellation {
                call.cancel()
            }

            call.enqueue(
                object : Callback {
                    override fun onFailure(
                        call: Call,
                        e: IOException,
                    ) {
                        continuation.resumeWithException(e)
                    }

                    override fun onResponse(
                        call: Call,
                        response: Response,
                    ) {
                        try {
                            if (!response.isSuccessful) {
                                continuation.resumeWithException(
                                    IOException("Download failed with status: ${response.code}"),
                                )
                                return
                            }

                            val body = response.body ?: throw IOException("Response body is null")
                            val contentLength = body.contentLength()

                            if (onProgress != null && contentLength > 0) {
                                // Download with progress tracking
                                val buffer = ByteArray(8192)
                                val outputBuffer = mutableListOf<Byte>()
                                var totalBytesRead = 0L

                                body.byteStream().use { inputStream ->
                                    var bytesRead: Int
                                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                                        outputBuffer.addAll(buffer.take(bytesRead))
                                        totalBytesRead += bytesRead
                                        onProgress(totalBytesRead, contentLength)
                                    }
                                }

                                continuation.resume(outputBuffer.toByteArray())
                            } else {
                                // Simple download without progress
                                val bytes = body.bytes()
                                continuation.resume(bytes)
                            }
                        } catch (e: Exception) {
                            continuation.resumeWithException(e)
                        } finally {
                            response.close()
                        }
                    }
                },
            )
        }
    }

    override suspend fun upload(
        url: String,
        data: ByteArray,
        headers: Map<String, String>,
        onProgress: ((bytesUploaded: Long, totalBytes: Long) -> Unit)?,
    ): HttpResponse = postWithProgress(url, data, headers, onProgress)

    /**
     * Multipart form upload
     */
    suspend fun multipartUpload(
        url: String,
        parts: List<MultipartPart>,
        headers: Map<String, String> = emptyMap(),
        onProgress: ((bytesUploaded: Long, totalBytes: Long) -> Unit)? = null,
    ): HttpResponse {
        val multipartBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)

        parts.forEach { part ->
            when (part) {
                is MultipartPart.FormField -> {
                    multipartBuilder.addFormDataPart(part.name, part.value)
                }
                is MultipartPart.FileField -> {
                    val mediaType = part.contentType?.toMediaType() ?: "application/octet-stream".toMediaType()
                    multipartBuilder.addFormDataPart(
                        part.name,
                        part.filename,
                        part.data.toRequestBody(mediaType),
                    )
                }
            }
        }

        val multipartBody = multipartBuilder.build()
        val requestBody =
            if (onProgress != null) {
                ProgressRequestBody(multipartBody, onProgress)
            } else {
                multipartBody
            }

        val request =
            Request
                .Builder()
                .url(url)
                .apply {
                    (defaultHeaders + headers).forEach { (key, value) ->
                        addHeader(key, value)
                    }
                }.post(requestBody)
                .build()

        return executeRequest(request)
    }

    override fun setDefaultTimeout(timeoutMillis: Long) {
        // Note: OkHttpClient is immutable, so this method doesn't change the existing client
        // In a production implementation, you'd need to rebuild the client
        logger.warn("setDefaultTimeout called but OkHttpClient is immutable. Use NetworkConfiguration instead.")
    }

    override fun setDefaultHeaders(headers: Map<String, String>) {
        defaultHeaders = headers.toMutableMap()
    }

    override fun cancelAllRequests() {
        client.dispatcher.cancelAll()
    }

    private suspend fun executeRequest(request: Request): HttpResponse =
        suspendCancellableCoroutine { continuation ->
            val call = client.newCall(request)

            continuation.invokeOnCancellation {
                call.cancel()
            }

            call.enqueue(
                object : Callback {
                    override fun onFailure(
                        call: Call,
                        e: IOException,
                    ) {
                        continuation.resumeWithException(e)
                    }

                    override fun onResponse(
                        call: Call,
                        response: Response,
                    ) {
                        try {
                            val body = response.body?.bytes() ?: ByteArray(0)
                            val headers = response.headers.toMultimap()

                            continuation.resume(
                                HttpResponse(
                                    statusCode = response.code,
                                    body = body,
                                    headers = headers,
                                ),
                            )
                        } catch (e: Exception) {
                            continuation.resumeWithException(e)
                        } finally {
                            response.close()
                        }
                    }
                },
            )
        }
}

/**
 * RequestBody wrapper that reports upload progress
 */
private class ProgressRequestBody(
    private val delegate: RequestBody,
    private val progressCallback: (bytesUploaded: Long, totalBytes: Long) -> Unit,
) : RequestBody() {
    override fun contentType(): MediaType? = delegate.contentType()

    override fun contentLength(): Long = delegate.contentLength()

    override fun writeTo(sink: BufferedSink) {
        val progressSink = ProgressSink(sink, contentLength(), progressCallback)
        val bufferedSink = progressSink.buffer()
        delegate.writeTo(bufferedSink)
        bufferedSink.flush()
    }
}

/**
 * Sink wrapper that reports progress
 */
private class ProgressSink(
    delegate: Sink,
    private val totalBytes: Long,
    private val progressCallback: (bytesUploaded: Long, totalBytes: Long) -> Unit,
) : ForwardingSink(delegate) {
    private var bytesWritten = 0L

    override fun write(
        source: Buffer,
        byteCount: Long,
    ) {
        super.write(source, byteCount)
        bytesWritten += byteCount
        progressCallback(bytesWritten, totalBytes)
    }
}

/**
 * Factory function to create HttpClient for JVM and Android
 */
actual fun createHttpClient(): HttpClient = OkHttpEngine()

/**
 * Factory function to create configured HttpClient
 */
actual fun createHttpClient(config: NetworkConfiguration): HttpClient = OkHttpEngine(config)
