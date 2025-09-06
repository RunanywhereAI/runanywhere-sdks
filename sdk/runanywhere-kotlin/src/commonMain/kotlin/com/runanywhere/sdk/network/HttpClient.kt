package com.runanywhere.sdk.network

/**
 * HTTP response data class
 */
data class HttpResponse(
    val statusCode: Int,
    val body: ByteArray,
    val headers: Map<String, List<String>> = emptyMap()
) {
    val isSuccessful: Boolean
        get() = statusCode in 200..299

    fun bodyAsString(): String = body.decodeToString()

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is HttpResponse) return false

        if (statusCode != other.statusCode) return false
        if (!body.contentEquals(other.body)) return false
        if (headers != other.headers) return false

        return true
    }

    override fun hashCode(): Int {
        var result = statusCode
        result = 31 * result + body.contentHashCode()
        result = 31 * result + headers.hashCode()
        return result
    }
}

/**
 * Platform-agnostic HTTP client interface
 * Provides common HTTP operations that are implemented differently on each platform
 */
interface HttpClient {
    /**
     * Perform a GET request
     */
    suspend fun get(
        url: String,
        headers: Map<String, String> = emptyMap()
    ): HttpResponse

    /**
     * Perform a POST request
     */
    suspend fun post(
        url: String,
        body: ByteArray,
        headers: Map<String, String> = emptyMap()
    ): HttpResponse

    /**
     * Perform a PUT request
     */
    suspend fun put(
        url: String,
        body: ByteArray,
        headers: Map<String, String> = emptyMap()
    ): HttpResponse

    /**
     * Perform a DELETE request
     */
    suspend fun delete(
        url: String,
        headers: Map<String, String> = emptyMap()
    ): HttpResponse

    /**
     * Download a file with progress callback
     */
    suspend fun download(
        url: String,
        headers: Map<String, String> = emptyMap(),
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)? = null
    ): ByteArray

    /**
     * Upload a file with progress callback
     */
    suspend fun upload(
        url: String,
        data: ByteArray,
        headers: Map<String, String> = emptyMap(),
        onProgress: ((bytesUploaded: Long, totalBytes: Long) -> Unit)? = null
    ): HttpResponse

    /**
     * Set a default timeout for all requests
     */
    fun setDefaultTimeout(timeoutMillis: Long)

    /**
     * Set default headers that will be included in all requests
     */
    fun setDefaultHeaders(headers: Map<String, String>)
}

/**
 * Expected to be provided by each platform
 */
expect fun createHttpClient(): HttpClient
