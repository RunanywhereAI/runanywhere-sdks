package com.runanywhere.sdk.network

/**
 * Multipart form data support for HTTP clients
 */

/**
 * Multipart form data part definitions
 */
sealed class MultipartPart {
    data class FormField(
        val name: String,
        val value: String,
    ) : MultipartPart()

    data class FileField(
        val name: String,
        val filename: String,
        val data: ByteArray,
        val contentType: String? = null,
    ) : MultipartPart() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is FileField) return false
            if (name != other.name) return false
            if (filename != other.filename) return false
            if (!data.contentEquals(other.data)) return false
            if (contentType != other.contentType) return false
            return true
        }

        override fun hashCode(): Int {
            var result = name.hashCode()
            result = 31 * result + filename.hashCode()
            result = 31 * result + data.contentHashCode()
            result = 31 * result + (contentType?.hashCode() ?: 0)
            return result
        }
    }
}

/**
 * Request cancellation support
 */
interface CancellableRequest {
    fun cancel()

    val isCancelled: Boolean
}

/**
 * HTTP request builder for complex requests
 */
class HttpRequestBuilder {
    private val headers = mutableMapOf<String, String>()
    private var body: ByteArray? = null
    private var multipartParts: List<MultipartPart>? = null

    fun header(
        name: String,
        value: String,
    ) = apply {
        headers[name] = value
    }

    fun headers(headerMap: Map<String, String>) =
        apply {
            headers.putAll(headerMap)
        }

    fun body(data: ByteArray) =
        apply {
            this.body = data
            this.multipartParts = null // Clear multipart if body is set
        }

    fun multipart(parts: List<MultipartPart>) =
        apply {
            this.multipartParts = parts
            this.body = null // Clear body if multipart is set
        }

    internal fun build() =
        HttpRequestData(
            headers = headers.toMap(),
            body = body,
            multipartParts = multipartParts,
        )
}

/**
 * Internal request data structure
 */
internal data class HttpRequestData(
    val headers: Map<String, String>,
    val body: ByteArray?,
    val multipartParts: List<MultipartPart>?,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is HttpRequestData) return false
        if (headers != other.headers) return false
        if (body != null) {
            if (other.body == null) return false
            if (!body.contentEquals(other.body)) return false
        } else if (other.body != null) {
            return false
        }
        if (multipartParts != other.multipartParts) return false
        return true
    }

    override fun hashCode(): Int {
        var result = headers.hashCode()
        result = 31 * result + (body?.contentHashCode() ?: 0)
        result = 31 * result + (multipartParts?.hashCode() ?: 0)
        return result
    }
}
