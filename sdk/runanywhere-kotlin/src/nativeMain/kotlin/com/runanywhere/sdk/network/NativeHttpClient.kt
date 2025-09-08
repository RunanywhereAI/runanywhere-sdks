package com.runanywhere.sdk.network

/**
 * Native implementation of HttpClient
 * This is a mock implementation for native platforms
 * In production, you would use platform-specific HTTP libraries
 */
internal class NativeHttpClient : HttpClient {

    private var defaultHeaders = mutableMapOf<String, String>()
    private var timeoutMillis = 30_000L

    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        // Mock implementation for native platforms
        return HttpResponse(
            statusCode = 200,
            body = "Mock response for GET $url".encodeToByteArray(),
            headers = mapOf("Content-Type" to listOf("text/plain"))
        )
    }

    override suspend fun post(
        url: String,
        body: ByteArray,
        headers: Map<String, String>
    ): HttpResponse {
        // Mock implementation for native platforms
        return HttpResponse(
            statusCode = 201,
            body = "Mock response for POST $url".encodeToByteArray(),
            headers = mapOf("Content-Type" to listOf("text/plain"))
        )
    }

    override suspend fun put(
        url: String,
        body: ByteArray,
        headers: Map<String, String>
    ): HttpResponse {
        // Mock implementation for native platforms
        return HttpResponse(
            statusCode = 200,
            body = "Mock response for PUT $url".encodeToByteArray(),
            headers = mapOf("Content-Type" to listOf("text/plain"))
        )
    }

    override suspend fun delete(url: String, headers: Map<String, String>): HttpResponse {
        // Mock implementation for native platforms
        return HttpResponse(
            statusCode = 204,
            body = ByteArray(0),
            headers = emptyMap()
        )
    }

    override suspend fun download(
        url: String,
        headers: Map<String, String>,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?
    ): ByteArray {
        // Mock download implementation
        val mockData = "Mock downloaded content from $url".encodeToByteArray()
        onProgress?.invoke(mockData.size.toLong(), mockData.size.toLong())
        return mockData
    }

    override suspend fun upload(
        url: String,
        data: ByteArray,
        headers: Map<String, String>,
        onProgress: ((bytesUploaded: Long, totalBytes: Long) -> Unit)?
    ): HttpResponse {
        // Mock upload implementation
        onProgress?.invoke(data.size.toLong(), data.size.toLong())
        return HttpResponse(
            statusCode = 201,
            body = "Mock upload response".encodeToByteArray(),
            headers = mapOf("Content-Type" to listOf("text/plain"))
        )
    }

    override fun setDefaultTimeout(timeoutMillis: Long) {
        this.timeoutMillis = timeoutMillis
    }

    override fun setDefaultHeaders(headers: Map<String, String>) {
        defaultHeaders = headers.toMutableMap()
    }
}

/**
 * Factory function to create HttpClient for native platforms
 */
actual fun createHttpClient(): HttpClient = NativeHttpClient()

/**
 * Factory function to create configured HttpClient for native platforms
 */
actual fun createHttpClient(config: NetworkConfiguration): HttpClient = NativeHttpClient()
