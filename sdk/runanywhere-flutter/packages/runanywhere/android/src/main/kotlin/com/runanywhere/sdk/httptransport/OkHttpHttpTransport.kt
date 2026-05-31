/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform HTTP transport adapter — Flutter plugin copy.
 *
 * This file is BYTE-FOR-BYTE COMPATIBLE with the Kotlin SDK's canonical
 *   sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/httptransport/OkHttpHttpTransport.kt
 * minus the Kotlin-SDK-only `SDKLogger` dependency (we use android.util.Log).
 *
 * Why duplicate? The Flutter plugin does NOT depend on the Kotlin SDK module —
 * it loads `librunanywhere_jni.so` directly. The C++ JNI shim
 *   sdk/runanywhere-commons/src/jni/okhttp_transport_adapter.cpp:557
 * does FindClass("com/runanywhere/sdk/httptransport/OkHttpHttpTransport"),
 * so this class MUST live at the exact same package+name. ClassNotFound
 * here means rc=-805 (RAC_ERROR_INTERNAL) on registration, no HTTP transport
 * vtable installed, and every `rac_http_request_send` returns -801.
 *
 * Mirrors Swift's `URLSessionHttpTransport` API surface and the iOS pod's
 * ObjC++ vtable behaviour.
 */

package com.runanywhere.sdk.httptransport

import android.util.Log
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import okhttp3.Call
import okhttp3.Headers
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.time.Duration
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * OkHttp-backed HTTP transport adapter.
 *
 * Registers a static `rac_http_transport_ops` vtable with the C core so
 * every `rac_http_request_send` / `_stream` / `_resume` call is serviced
 * by OkHttp on Android. Safe to call [register] multiple times — subsequent
 * calls are no-ops (the underlying JNI adapter is idempotent).
 *
 * Mirrors the Swift `URLSessionHttpTransport` API surface:
 *   - [register] / [unregister] install / remove the vtable
 *   - [executeRequest] backs the `request_send` slot (blocking, buffered)
 *   - [executeStreamingRequest] backs the `request_stream` slot
 *   - [executeResumeRequest] backs the `request_resume` slot (Range header)
 *   - [setHttpClient] lets hosts swap in a custom OkHttpClient
 */
object OkHttpHttpTransport {
    private const val TAG = "OkHttpHttpTransport"

    /** Chunk size used for streaming body delivery (32 KB matches Okio's default). */
    private const val STREAM_CHUNK_SIZE = 32 * 1024

    /** Default OkHttp client. Lazily built on first use. Mirrors Swift's `sharedSession`. */
    private val defaultClient: OkHttpClient by lazy {
        OkHttpClient
            .Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    /**
     * Dedicated streaming OkHttp client. Mirrors the Swift adapter's per-call
     * streaming session built with `timeoutIntervalForResource = 24 * 60 * 60`.
     * A multi-GB GGUF download over a slow cellular link can legitimately run
     * for hours, so the read timeout is bumped from the default 120s to 24h.
     */
    private val streamingClient: OkHttpClient
        get() {
            val base = clientRef.get() ?: defaultClient
            return base
                .newBuilder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .readTimeout(Duration.ofHours(24))
                .writeTimeout(60, TimeUnit.SECONDS)
                .build()
        }

    /** Active client reference. Hosts can swap via [setHttpClient]. */
    private val clientRef: AtomicReference<OkHttpClient?> = AtomicReference(null)

    /** Monotonic counter for keying the in-flight stream registry. */
    private val streamIdCounter: AtomicLong = AtomicLong(0L)

    /**
     * Registry of in-flight streaming [Call] objects keyed by a monotonic id.
     * Mirrors Swift's `StreamRegistry`. Used by [cancelAllStreams] to drive
     * `Call.cancel()` on every active download during SDK teardown.
     */
    private val inFlightStreams: ConcurrentHashMap<Long, Call> = ConcurrentHashMap()

    /** Registration state guard (mirrors Swift's `OSAllocatedUnfairLock<Bool>`). */
    private val registrationState: AtomicReference<Boolean> = AtomicReference(false)

    // ---------------------------------------------------------------------
    // Public entry points (mirrors Swift URLSessionHttpTransport)
    // ---------------------------------------------------------------------

    /**
     * Install the OkHttp adapter as the active HTTP transport.
     * Idempotent — subsequent calls are no-ops.
     *
     * Returns `true` on success, `false` if the native bridge symbol is
     * missing or registration failed in C++.
     */
    @JvmStatic
    fun register(): Boolean {
        val alreadyRegistered = !registrationState.compareAndSet(false, true)
        if (alreadyRegistered) {
            Log.d(TAG, "OkHttp HTTP transport already registered (skipping)")
            return true
        }

        return try {
            val rc = RunAnywhereBridge.racHttpTransportRegisterOkHttp()
            if (rc == 0) {
                Log.i(TAG, "OkHttp HTTP transport registered (system trust store + proxy)")
                true
            } else {
                Log.w(TAG, "OkHttp HTTP transport registration returned rc=$rc; falling back to libcurl")
                registrationState.set(false)
                false
            }
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "OkHttp HTTP transport symbol missing in native lib: ${e.message}")
            registrationState.set(false)
            false
        } catch (e: Throwable) {
            Log.w(TAG, "OkHttp HTTP transport registration failed: ${e.message}")
            registrationState.set(false)
            false
        }
    }

    /**
     * Restore the default libcurl transport. Best-effort; drains in-flight
     * streams via [cancelAllStreams]. Mirrors Swift's `unregister()`.
     */
    @JvmStatic
    fun unregister() {
        val wasRegistered = registrationState.getAndSet(false)
        if (!wasRegistered) return
        try {
            RunAnywhereBridge.racHttpTransportUnregisterOkHttp()
            cancelAllStreams()
            Log.i(TAG, "OkHttp HTTP transport unregistered")
        } catch (_: UnsatisfiedLinkError) {
            // Symbol not present — nothing to do.
        } catch (e: Throwable) {
            Log.w(TAG, "OkHttp HTTP transport unregistration failed: ${e.message}")
        }
    }

    /**
     * Cancel every in-flight streaming / resume call. Mirrors Swift's
     * `cancelAllStreams()`. Use when the SDK is tearing down.
     */
    @JvmStatic
    fun cancelAllStreams() {
        val snapshot = inFlightStreams.values.toList()
        for (call in snapshot) {
            call.cancel()
        }
    }

    /**
     * Install a custom [OkHttpClient]. Mirrors Swift's
     * `register(streamingSession:)`. Safe to call at any time.
     */
    @JvmStatic
    fun setHttpClient(client: OkHttpClient?) {
        clientRef.set(client)
    }

    /** Returns the currently installed custom client, or null if using default. */
    @JvmStatic
    fun getHttpClient(): OkHttpClient? = clientRef.get()

    // ---------------------------------------------------------------------
    // C-callback entry points (invoked by JNI; mirror Swift's
    // `cRequestSend` / `cRequestStream` / `cRequestResume` trampolines)
    // ---------------------------------------------------------------------

    /**
     * `request_send` vtable slot — blocking single-shot request. Invoked
     * from JNI via `CallStaticObjectMethod`. Returns a [HttpResponse].
     */
    @JvmStatic
    fun executeRequest(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
        timeoutMs: Long,
    ): HttpResponse {
        return try {
            val request = buildRequest(method, url, headersFlat, bodyBytes, resumeFromByte = 0L)
            val clientForCall = resolveClient(timeoutMs)

            clientForCall.newCall(request).execute().use { resp ->
                val headerPairs = flattenHeaders(resp.headers)
                val responseBody = resp.body?.bytes() ?: ByteArray(0)
                HttpResponse(
                    statusCode = resp.code,
                    headers = headerPairs,
                    bodyBytes = responseBody,
                    errorMessage = null,
                )
            }
        } catch (e: Throwable) {
            HttpResponse(
                statusCode = 0,
                headers = emptyArray(),
                bodyBytes = ByteArray(0),
                errorMessage = "${e.javaClass.simpleName}: ${e.message ?: "unknown"}",
            )
        }
    }

    /**
     * `request_stream` vtable slot — streams body via chunk callback.
     * Cancellation: when the native side returns `false` from
     * [deliverChunkNative], we call [okhttp3.Call.cancel] to abort.
     */
    @JvmStatic
    fun executeStreamingRequest(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
        timeoutMs: Long,
        nativeCallback: Long,
        nativeUserData: Long,
    ): StreamResponse {
        return streamInternal(
            method = method,
            url = url,
            headersFlat = headersFlat,
            bodyBytes = bodyBytes,
            timeoutMs = timeoutMs,
            nativeCallback = nativeCallback,
            nativeUserData = nativeUserData,
            resumeFromByte = 0L,
        )
    }

    /**
     * `request_resume` vtable slot — identical to [executeStreamingRequest]
     * but attaches a `Range: bytes=N-` header before dispatching. Mirrors
     * Swift's `cRequestResume`.
     */
    @JvmStatic
    fun executeResumeRequest(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
        timeoutMs: Long,
        resumeFromByte: Long,
        nativeCallback: Long,
        nativeUserData: Long,
    ): StreamResponse {
        return streamInternal(
            method = method,
            url = url,
            headersFlat = headersFlat,
            bodyBytes = bodyBytes,
            timeoutMs = timeoutMs,
            nativeCallback = nativeCallback,
            nativeUserData = nativeUserData,
            resumeFromByte = resumeFromByte,
        )
    }

    // ---------------------------------------------------------------------
    // Native bridge
    // ---------------------------------------------------------------------

    /**
     * Native bridge: hands a chunk to the C `rac_http_body_chunk_fn` pointed
     * to by [nativeCallback]. Implemented in `okhttp_transport_adapter.cpp`.
     * Returns `false` when the native side wants to cancel the transfer.
     */
    @JvmStatic
    private external fun deliverChunkNative(
        nativeCallback: Long,
        nativeUserData: Long,
        chunk: ByteArray,
        chunkLen: Int,
        totalWritten: Long,
        contentLength: Long,
    ): Boolean

    // ---------------------------------------------------------------------
    // Streaming core (shared between request_stream + request_resume)
    // ---------------------------------------------------------------------

    private fun streamInternal(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
        timeoutMs: Long,
        nativeCallback: Long,
        nativeUserData: Long,
        resumeFromByte: Long,
    ): StreamResponse {
        val streamId = streamIdCounter.incrementAndGet()
        var registered = false
        return try {
            val request = buildRequest(method, url, headersFlat, bodyBytes, resumeFromByte)
            val clientForCall = resolveStreamingClient(timeoutMs)

            val call = clientForCall.newCall(request)
            inFlightStreams[streamId] = call
            registered = true

            call.execute().use { resp ->
                val headerPairs = buildResponseHeaders(resp.headers, resumeFromByte, resp.code)
                val body =
                    resp.body
                        ?: return StreamResponse(
                            statusCode = resp.code,
                            headers = headerPairs,
                            errorMessage = null,
                            cancelled = false,
                        )

                val honoredRange = resp.code == 206 && resumeFromByte > 0
                val rawContentLength = if (body.contentLength() >= 0) body.contentLength() else 0L
                val contentLength =
                    if (honoredRange && rawContentLength > 0) {
                        rawContentLength + resumeFromByte
                    } else {
                        rawContentLength
                    }
                val totalRead = if (honoredRange) resumeFromByte else 0L

                val cancelled = drainBody(body, call, contentLength, totalRead, nativeCallback, nativeUserData)

                StreamResponse(
                    statusCode = resp.code,
                    headers = headerPairs,
                    errorMessage = null,
                    cancelled = cancelled,
                )
            }
        } catch (e: Throwable) {
            StreamResponse(
                statusCode = 0,
                headers = emptyArray(),
                errorMessage = "${e.javaClass.simpleName}: ${e.message ?: "unknown"}",
                cancelled = false,
            )
        } finally {
            if (registered) {
                inFlightStreams.remove(streamId)
            }
        }
    }

    /**
     * Drains the response body chunk-by-chunk, forwarding each chunk to the
     * native callback. Returns `true` if the transfer was cancelled.
     */
    private fun drainBody(
        body: okhttp3.ResponseBody,
        call: Call,
        contentLength: Long,
        initialTotalRead: Long,
        nativeCallback: Long,
        nativeUserData: Long,
    ): Boolean {
        val buffer = ByteArray(STREAM_CHUNK_SIZE)
        var totalRead = initialTotalRead
        var cancelled = false

        body.byteStream().use { input ->
            while (true) {
                val n =
                    try {
                        input.read(buffer)
                    } catch (io: IOException) {
                        if (call.isCanceled()) {
                            cancelled = true
                            break
                        }
                        throw io
                    }
                if (n < 0) break
                if (n == 0) continue

                totalRead += n
                val chunk = if (n == buffer.size) buffer else buffer.copyOf(n)
                val keepGoing =
                    deliverChunkNative(
                        nativeCallback,
                        nativeUserData,
                        chunk,
                        n,
                        totalRead,
                        contentLength,
                    )
                if (!keepGoing) {
                    cancelled = true
                    call.cancel()
                    break
                }
            }
        }
        return cancelled
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private fun buildRequest(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
        resumeFromByte: Long,
    ): Request {
        val builder = Request.Builder().url(url)

        var contentType: String? = null
        var i = 0
        while (i < headersFlat.size - 1) {
            val name = headersFlat[i]
            val value = headersFlat[i + 1]
            builder.addHeader(name, value)
            if (name.equals("Content-Type", ignoreCase = true)) {
                contentType = value
            }
            i += 2
        }

        if (resumeFromByte > 0) {
            builder.header("Range", "bytes=$resumeFromByte-")
        }

        val body: RequestBody? =
            bodyBytes?.toRequestBody(
                contentType = contentType?.toMediaTypeOrNull(),
            )

        when (method.uppercase()) {
            "GET" -> builder.get()
            "POST" -> builder.post(body ?: EMPTY_BODY)
            "PUT" -> builder.put(body ?: EMPTY_BODY)
            "DELETE" -> if (body != null) builder.delete(body) else builder.delete()
            "PATCH" -> builder.patch(body ?: EMPTY_BODY)
            "HEAD" -> builder.head()
            else -> builder.method(method, body)
        }

        return builder.build()
    }

    private fun resolveClient(timeoutMs: Long): OkHttpClient {
        val base = clientRef.get() ?: defaultClient
        return if (timeoutMs > 0) {
            base
                .newBuilder()
                .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                .build()
        } else {
            base
        }
    }

    private fun resolveStreamingClient(timeoutMs: Long): OkHttpClient {
        val base = streamingClient
        return if (timeoutMs > 0) {
            base
                .newBuilder()
                .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                .build()
        } else {
            base
        }
    }

    private fun flattenHeaders(headers: Headers): Array<String> {
        val pairs = ArrayList<String>(headers.size * 2)
        for ((name, value) in headers) {
            pairs.add(name)
            pairs.add(value)
        }
        return pairs.toTypedArray()
    }

    /**
     * Build the response headers array, appending the synthetic
     * `X-RAC-Range-Honored` marker when the caller requested a resume.
     */
    private fun buildResponseHeaders(
        responseHeaders: Headers,
        resumeFromByte: Long,
        statusCode: Int,
    ): Array<String> {
        val pairs = ArrayList<String>(responseHeaders.size * 2 + 2)
        for ((name, value) in responseHeaders) {
            pairs.add(name)
            pairs.add(value)
        }
        if (resumeFromByte > 0) {
            val honored = statusCode == 206
            pairs.add("X-RAC-Range-Honored")
            pairs.add(if (honored) "true" else "false")
        }
        return pairs.toTypedArray()
    }

    // ---------------------------------------------------------------------
    // Response DTOs
    // ---------------------------------------------------------------------

    /**
     * Response DTO for the blocking path. Layout matches the JNI
     * FindClass/GetFieldID lookups in `okhttp_transport_adapter.cpp` — do NOT
     * rename fields without updating the C++ side.
     */
    class HttpResponse(
        @JvmField val statusCode: Int,
        @JvmField val headers: Array<String>,
        @JvmField val bodyBytes: ByteArray,
        @JvmField val errorMessage: String?,
    )

    /**
     * Response DTO for the streaming path. Body is delivered chunk-by-chunk
     * through [deliverChunkNative]; this struct only carries status + headers
     * metadata back to C++ for the `rac_http_response_t`.
     */
    class StreamResponse(
        @JvmField val statusCode: Int,
        @JvmField val headers: Array<String>,
        @JvmField val errorMessage: String?,
        @JvmField val cancelled: Boolean,
    )

    /** Empty body used for bodied verbs called without a payload. */
    private val EMPTY_BODY: RequestBody = ByteArray(0).toRequestBody()
}
