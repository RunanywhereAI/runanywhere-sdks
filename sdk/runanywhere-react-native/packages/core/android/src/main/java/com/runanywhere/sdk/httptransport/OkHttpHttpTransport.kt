/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Platform HTTP transport adapter — React Native Android.
 *
 * The C++ JNI bridge (commons' okhttp_transport_adapter.cpp, compiled into
 * librunanywhere_jni.so) does FindClass on
 * `com/runanywhere/sdk/httptransport/OkHttpHttpTransport` and dispatches
 * `executeRequest` / `executeStreamingRequest` / `executeResumeRequest`
 * through the resolved methods. Keeping the package + class + method
 * signatures aligned with the Kotlin SDK lets RN reuse the same native
 * adapter symbols instead of forking the source file.
 *
 * If both the Kotlin SDK and the RN core appear on the same classpath,
 * Gradle's duplicate-class detector flags this file — consumers are
 * expected to pick a single integration path.
 */

package com.runanywhere.sdk.httptransport

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
 * Platform HTTP transport adapter. C++ core calls into this class via JNI when
 * the OkHttp transport is registered. OkHttp gives us the system CA store,
 * proxies, NetworkSecurityConfig, HTTP/2, cert pinning, user-CAs for free.
 *
 * Layout — fields, methods, and nested DTO names — must stay in sync with
 * the JNI FindClass/GetMethodID/GetFieldID calls in
 * `sdk/runanywhere-commons/src/jni/okhttp_transport_adapter.cpp`.
 *
 * Mirrors the Swift `URLSessionHttpTransport` API surface:
 *   - [register] / [unregister] install / remove the vtable
 *   - [executeRequest] backs the `request_send` slot (blocking, buffered)
 *   - [executeStreamingRequest] backs the `request_stream` slot
 *   - [executeResumeRequest] backs the `request_resume` slot (Range header)
 *   - [setHttpClient] lets hosts swap in a custom OkHttpClient
 */
object OkHttpHttpTransport {
    private const val STREAM_CHUNK_SIZE = 256 * 1024

    /** Default OkHttp client. Lazily built on first use. Mirrors Swift's `sharedSession`. */
    private val defaultClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
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
     * Connect / write timeouts retain the default's tighter bounds because
     * those phases still complete in seconds even on slow links.
     *
     * Built off of [defaultClient] (or a host-installed override) via
     * `.newBuilder()` so any custom interceptors / cert pinners installed by
     * [setHttpClient] are preserved on the streaming path.
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

    /**
     * Active client reference. App teams can swap this via [setHttpClient] to
     * plug in their own interceptors, custom cert pinners, DNS resolvers, or a
     * WorkManager-friendly variant with longer timeouts.
     *
     * Reads are lock-free (AtomicReference); writes are atomic.
     */
    private val clientRef: AtomicReference<OkHttpClient?> = AtomicReference(null)

    /** Monotonic counter for keying the in-flight stream registry. */
    private val streamIdCounter: AtomicLong = AtomicLong(0L)

    /**
     * Registry of in-flight streaming [StreamSlot]s keyed by a monotonic id.
     * Mirrors Swift's `StreamRegistry` and is used by [cancelAllStreams] to
     * drive `Call.cancel()` on every active download during SDK teardown.
     *
     * Each slot is registered BEFORE `newCall()` runs so a `cancelAllStreams()`
     * that lands between slot creation and `newCall(request)` is observed. When
     * the slot's [StreamSlot.call] is still null at cancel time, the slot's
     * `cancelRequested` flag is set and the streaming caller invokes
     * `call.cancel()` itself once newCall returns.
     */
    private val inFlightStreams: ConcurrentHashMap<Long, StreamSlot> = ConcurrentHashMap()

    /**
     * Per-stream slot tracking the eventual [Call] together with a
     * cancel-requested flag. Pre-registered before `newCall(request)` so a
     * [cancelAllStreams] that races startup can mark the slot for immediate
     * cancellation once the Call materializes.
     *
     * Fields are guarded by the slot's own monitor (`synchronized(this)`).
     */
    private class StreamSlot {
        var call: Call? = null
        var cancelRequested: Boolean = false
    }

    /** Registration state guard. Mirrors Swift's `OSAllocatedUnfairLock<Bool>`. */
    private val registrationState: AtomicReference<Boolean> = AtomicReference(false)

    // -------------------------------------------------------------------------
    // Public entry points (mirrors Swift URLSessionHttpTransport)
    // -------------------------------------------------------------------------

    /**
     * Install the OkHttp adapter as the active HTTP transport.
     * Idempotent — subsequent calls are no-ops.
     *
     * Mirrors Swift's `URLSessionHttpTransport.register()`. The JNI side
     * caches method IDs + the global class reference, then installs a static
     * `rac_http_transport_ops_t` vtable via `rac_http_transport_register`.
     *
     * @return `true` on success, `false` if the native bridge symbol is missing
     *         or registration failed in C++.
     */
    @JvmStatic
    fun register(): Boolean {
        val alreadyRegistered = !registrationState.compareAndSet(false, true)
        if (alreadyRegistered) return true

        return try {
            val rc = com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racHttpTransportRegisterOkHttp()
            if (rc == 0) {
                true
            } else {
                registrationState.set(false)
                false
            }
        } catch (_: UnsatisfiedLinkError) {
            registrationState.set(false)
            false
        } catch (_: Throwable) {
            registrationState.set(false)
            false
        }
    }

    /**
     * Restore the default libcurl transport. Best-effort — any failure is
     * logged but does not throw. Also drains the in-flight stream registry via
     * [cancelAllStreams].
     *
     * Mirrors Swift's `URLSessionHttpTransport.unregister()`.
     */
    @JvmStatic
    fun unregister() {
        val wasRegistered = registrationState.getAndSet(false)
        if (!wasRegistered) return
        try {
            com.runanywhere.sdk.native.bridge.RunAnywhereBridge.racHttpTransportUnregisterOkHttp()
            cancelAllStreams()
        } catch (_: UnsatisfiedLinkError) {
            // Symbol not present — nothing to do.
        } catch (_: Throwable) {
            // Best-effort.
        }
    }

    /**
     * Cancel every in-flight streaming / resume call. Each pending chunk
     * callback surfaces back to its caller with `cancelled = true`.
     * Complements the per-callback `return false` cancel contract — use this
     * when the SDK is tearing down.
     *
     * Mirrors Swift's `URLSessionHttpTransport.cancelAllStreams()`.
     */
    @JvmStatic
    fun cancelAllStreams() {
        val snapshot = inFlightStreams.values.toList()
        for (slot in snapshot) {
            val call = synchronized(slot) {
                slot.cancelRequested = true
                slot.call
            }
            call?.cancel()
        }
    }

    /**
     * Install a custom [OkHttpClient]. Safe to call at any time; subsequent
     * requests pick up the new client. Pass `null` to fall back to the default.
     *
     * Mirrors Swift's `URLSessionHttpTransport.register(streamingSession:)`.
     */
    @JvmStatic
    fun setHttpClient(client: OkHttpClient?) {
        clientRef.set(client)
    }

    /** Returns the currently installed custom client, or null if using default. */
    @JvmStatic
    fun getHttpClient(): OkHttpClient? = clientRef.get()

    // -------------------------------------------------------------------------
    // C-callback entry points (invoked by JNI)
    // -------------------------------------------------------------------------

    /**
     * `request_send` vtable slot — blocking single-shot request. Invoked
     * from JNI via `CallStaticObjectMethod`. Returns an [HttpResponse].
     *
     * @param method      HTTP method in uppercase ASCII ("GET"/"POST"/...).
     * @param url         Absolute HTTP/HTTPS URL.
     * @param headersFlat Flat `[k1, v1, k2, v2, ...]` header array.
     * @param bodyBytes   Request body bytes, or null for GET/HEAD.
     * @param timeoutMs   Call timeout in ms (0 = use the shared client defaults).
     * @return [HttpResponse]. On transport failure `statusCode == 0` and
     *         [HttpResponse.errorMessage] is non-null.
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
     * [deliverChunkNative], `Call.cancel()` aborts the TCP connection.
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
     *
     * Range-honored disclosure: a synthetic `X-RAC-Range-Honored` marker header
     * surfaces whether the server honored the Range (206) or replayed the full
     * file (200), so the C++ download manager can truncate if needed.
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

    // -------------------------------------------------------------------------
    // Native bridge
    // -------------------------------------------------------------------------

    @JvmStatic
    private external fun deliverChunkNative(
        nativeCallback: Long,
        nativeUserData: Long,
        chunk: ByteArray,
        chunkLen: Int,
        totalWritten: Long,
        contentLength: Long,
    ): Boolean

    // -------------------------------------------------------------------------
    // Streaming core (shared between request_stream + request_resume)
    // -------------------------------------------------------------------------

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
        // Pre-register the slot BEFORE building the Call so a cancelAllStreams()
        // that lands during startup observes this stream.
        val slot = StreamSlot()
        inFlightStreams[streamId] = slot
        return try {
            val request = buildRequest(method, url, headersFlat, bodyBytes, resumeFromByte)
            // Streaming downloads use the dedicated streaming client with a
            // 24-hour read timeout (multi-GB GGUFs over slow links can take
            // hours); the default 120s would abort them mid-transfer.
            val clientForCall = resolveStreamingClient(timeoutMs)

            val call = clientForCall.newCall(request)
            // Publish the Call into the slot. If cancelAllStreams() landed
            // between slot pre-registration and now, cancel immediately.
            val cancelImmediately = synchronized(slot) {
                slot.call = call
                slot.cancelRequested
            }
            if (cancelImmediately) {
                call.cancel()
            }

            call.execute().use { resp ->
                val headerPairs = buildResponseHeaders(resp.headers, resumeFromByte, resp.code)
                val body = resp.body
                    ?: return StreamResponse(
                        statusCode = resp.code,
                        headers = headerPairs,
                        errorMessage = null,
                        cancelled = false,
                    )

                // Resume accounting: when the server honored the Range (206),
                // Content-Length is only the remaining bytes — add the resume
                // offset so chunk callbacks see a monotonic total_written.
                val honoredRange = resp.code == 206 && resumeFromByte > 0
                val rawContentLength = if (body.contentLength() >= 0) body.contentLength() else 0L
                val contentLength =
                    if (honoredRange && rawContentLength > 0) {
                        rawContentLength + resumeFromByte
                    } else {
                        rawContentLength
                    }
                var totalRead = if (honoredRange) resumeFromByte else 0L

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
            inFlightStreams.remove(streamId)
        }
    }

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
                val n = try {
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
                val keepGoing = deliverChunkNative(
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

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

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
            base.newBuilder()
                .callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
                .build()
        } else {
            base
        }
    }

    /**
     * Streaming path uses [streamingClient] (24h read timeout) as the base.
     * If the caller supplied an explicit per-request `timeoutMs`, layer it on
     * as a `callTimeout` — still lets the read timeout cap stalled reads at 24h.
     */
    private fun resolveStreamingClient(timeoutMs: Long): OkHttpClient {
        val base = streamingClient
        return if (timeoutMs > 0) {
            base.newBuilder()
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

    // -------------------------------------------------------------------------
    // Response DTOs
    // -------------------------------------------------------------------------

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

    private val EMPTY_BODY: RequestBody = ByteArray(0).toRequestBody()
}
