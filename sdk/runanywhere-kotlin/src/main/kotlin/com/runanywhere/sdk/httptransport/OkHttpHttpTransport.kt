/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * OkHttp-backed adapter for the cross-SDK HTTP transport vtable
 * (`rac_http_transport_*`). Registering this adapter routes every
 * `rac_http_request_*` call through OkHttp instead of the bundled
 * libcurl — so Android / JVM consumers inherit the system trust store,
 * configured proxies, HTTP/2, NetworkSecurityConfig, and user-installed
 * CAs for free.
 *
 * This file is the Kotlin parity for
 * `sdk/runanywhere-swift/Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift`.
 * The Swift adapter installs URLSession into the `rac_http_transport_ops_t`
 * vtable; this adapter installs OkHttp on the JVM/Android side.
 *
 * The C++ side of the bridge lives in
 * `sdk/runanywhere-commons/src/jni/okhttp_transport_adapter.cpp` and
 * resolves this class (`com/runanywhere/sdk/httptransport/OkHttpHttpTransport`)
 * directly.
 *
 * R3 additions (parity with Swift):
 *   - `executeResumeRequest()` with `Range: bytes=N-` header
 *     (Swift's `request_resume` vtable slot — the Kotlin side previously
 *     only covered `request_send` + `request_stream`).
 *
 * Threading: OkHttp is thread-safe; the singleton client is reused.
 * Each execute* call blocks the caller thread — the native JNI caller
 * is expected to run these off the main thread.
 */

package com.runanywhere.sdk.httptransport

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import okhttp3.Call
import okhttp3.Headers
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * OkHttp-backed HTTP transport adapter.
 *
 * Registers a static `rac_http_transport_ops` vtable with the C core so
 * every `rac_http_request_send` / `_stream` / `_resume` call is serviced
 * by OkHttp on Android / JVM. Safe to call [register] multiple times —
 * subsequent calls are no-ops (the underlying JNI adapter is idempotent).
 *
 * Mirrors the Swift `URLSessionHttpTransport` API surface:
 *   - [register] / [unregister] install / remove the vtable
 *   - [executeRequest] backs the `request_send` slot (blocking, buffered)
 *   - [executeStreamingRequest] backs the `request_stream` slot
 *   - [executeResumeRequest] backs the `request_resume` slot (Range header)
 *   - [setHttpClient] lets hosts swap in a custom OkHttpClient
 */
object OkHttpHttpTransport {
    private val logger = SDKLogger("OkHttpHttpTransport")

    /** Chunk size used for streaming body delivery (32 KB matches Okio's default). */
    private const val STREAM_CHUNK_SIZE = 32 * 1024

    /**
     * Default OkHttp client backing the buffered `request_send` path.
     * Lazily built on first use. Mirrors Swift's `sharedSession`
     * (`timeoutIntervalForRequest = 60`, `timeoutIntervalForResource = 600`):
     * the 60s read timeout is the per-read inactivity bound and the 600s
     * call timeout caps the whole transfer. URLSession has no separate
     * connect knob, so the 30s connect timeout is kept as a sane OkHttp
     * default. Per-request `timeoutMs` values layer a tighter `callTimeout`
     * via [resolveClient].
     */
    private val defaultClient: OkHttpClient by lazy {
        OkHttpClient
            .Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .callTimeout(600, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .build()
    }

    /**
     * Dedicated streaming OkHttp client. Mirrors the Swift adapter's per-call
     * streaming session built with `timeoutIntervalForResource = 24 * 60 * 60`.
     * A multi-GB GGUF download over a slow cellular link can legitimately run
     * for hours, so the read timeout is bumped from the buffered client's 60s
     * to 24h, and the call timeout is reset to 0 (unlimited) so the buffered
     * path's 600s overall cap is not inherited via `.newBuilder()`. Connect /
     * write timeouts retain the default's tighter bounds because those phases
     * still complete in seconds even on slow links.
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
                .readTimeout(24, TimeUnit.HOURS)
                .writeTimeout(60, TimeUnit.SECONDS)
                .callTimeout(0, TimeUnit.MILLISECONDS)
                .build()
        }

    /**
     * Active client reference. App teams can swap this via [setHttpClient] to
     * plug in their own interceptors (OkHttp Logging, Chucker), custom cert
     * pinners, DNS resolvers, or a WorkManager-friendly variant with longer
     * timeouts.
     *
     * Reads are lock-free (AtomicReference); writes are atomic.
     */
    private val clientRef: AtomicReference<OkHttpClient?> = AtomicReference(null)

    /**
     * Monotonic counter for keying the in-flight stream registry. OkHttp's
     * [Call] does not expose a stable identifier, so we mint our own.
     */
    private val streamIdCounter: AtomicLong = AtomicLong(0L)

    /**
     * Registry of in-flight streaming [StreamSlot]s keyed by a monotonic id.
     * Mirrors Swift's `StreamRegistry` (keyed by `URLSessionTask.taskIdentifier`)
     * and is used by [cancelAllStreams] to drive `Call.cancel()` on every
     * active download during SDK teardown.
     *
     * Each slot is registered BEFORE `newCall()` runs so a `cancelAllStreams()`
     * that lands between `streamIdCounter.incrementAndGet()` and the C
     * library's `newCall(request)` is observed. When the slot's [StreamSlot.call]
     * is still null at cancel time, the slot's `cancelRequested` flag is set
     * and the streaming caller invokes `call.cancel()` itself once newCall
     * returns. Without this, a cancel that races startup would miss the stream
     * entirely and the request would proceed past the teardown signal.
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

    /**
     * Registration state guard. `AtomicReference<Boolean>` is used instead of
     * a Java `synchronized` block so [register] / [unregister] stay non-blocking
     * on the SDK init path (mirrors Swift's `OSAllocatedUnfairLock<Bool>`).
     */
    private val registrationState: AtomicReference<Boolean> = AtomicReference(false)

    // Public entry points (mirrors Swift URLSessionHttpTransport)

    /**
     * Install the OkHttp adapter as the active HTTP transport.
     * Idempotent — subsequent calls are no-ops.
     *
     * Mirrors Swift's `URLSessionHttpTransport.register()`. The JNI side
     * (`okhttp_transport_adapter.cpp`) caches method IDs + the global
     * class reference, then installs a static `rac_http_transport_ops_t`
     * vtable via `rac_http_transport_register`.
     *
     * Returns `true` on success, `false` if the native bridge symbol is
     * missing (e.g. JNI library not loaded) or registration failed in C++.
     */
    @JvmStatic
    fun register(): Boolean {
        val alreadyRegistered = !registrationState.compareAndSet(false, true)
        if (alreadyRegistered) {
            logger.debug("OkHttp HTTP transport already registered (skipping)")
            return true
        }

        return try {
            val rc = RunAnywhereBridge.racHttpTransportRegisterOkHttp()
            if (rc == 0) {
                logger.info("OkHttp HTTP transport registered (system trust store + proxy)")
                true
            } else {
                logger.warn("OkHttp HTTP transport registration returned rc=$rc; falling back to libcurl")
                registrationState.set(false)
                false
            }
        } catch (e: UnsatisfiedLinkError) {
            logger.warn("OkHttp HTTP transport symbol missing in native lib: ${e.message}")
            registrationState.set(false)
            false
        } catch (e: Throwable) {
            logger.warn("OkHttp HTTP transport registration failed: ${e.message}")
            registrationState.set(false)
            false
        }
    }

    /**
     * Restore the default libcurl transport. Best-effort — any failure is
     * logged but does not throw. Mirrors Swift's
     * `URLSessionHttpTransport.unregister()`.
     *
     * Also drains the in-flight stream registry via [cancelAllStreams], so any
     * downloads still in flight surface as cancelled rather than tripping
     * mid-flight when the C++ vtable is yanked.
     */
    @JvmStatic
    fun unregister() {
        val wasRegistered = registrationState.getAndSet(false)
        if (!wasRegistered) return
        try {
            RunAnywhereBridge.racHttpTransportUnregisterOkHttp()
            cancelAllStreams()
            logger.info("OkHttp HTTP transport unregistered")
        } catch (_: UnsatisfiedLinkError) {
            // Symbol not present — nothing to do.
        } catch (e: Throwable) {
            logger.warn("OkHttp HTTP transport unregistration failed: ${e.message}")
        }
    }

    /**
     * Cancel every in-flight streaming / resume call. Each pending chunk
     * callback surfaces back to its caller with `cancelled = true` on the
     * returned [StreamResponse] (because [okhttp3.Call.cancel] surfaces as an
     * `IOException` that [drainBody] maps to a clean cancellation when
     * `call.isCanceled()` is true). Complements the per-callback
     * `return false` cancel contract — use this when the SDK is tearing down
     * and there is no callback on the stack to signal.
     *
     * Mirrors Swift's `URLSessionHttpTransport.cancelAllStreams()`.
     */
    @JvmStatic
    fun cancelAllStreams() {
        // Snapshot under the iterator, drive cancel() outside the slot's
        // monitor — the cancel races back through drainBody's IOException path
        // and attempts to remove(streamId).
        //
        // Slots that have already published their Call get cancelled directly.
        // Slots that are still mid-startup (Call not yet stored) get their
        // cancelRequested flag set; the streaming caller then runs
        // `call.cancel()` itself as soon as `newCall(request)` returns
        // (`streamInternal` checks `cancelRequested` immediately after the
        // slot is finalised).
        val snapshot = inFlightStreams.values.toList()
        for (slot in snapshot) {
            val call =
                synchronized(slot) {
                    slot.cancelRequested = true
                    slot.call
                }
            call?.cancel()
        }
    }

    /**
     * Install a custom [OkHttpClient]. This is the standard Android escape
     * hatch for apps that need to attach interceptors, custom SSL contexts,
     * Chucker, certificate pinners, or longer timeouts for WorkManager
     * downloads.
     *
     * Mirrors Swift's `URLSessionHttpTransport.register(streamingSession:)`.
     * Safe to call at any time; subsequent requests pick up the new client.
     * Pass `null` to fall back to the default client.
     *
     * Example:
     * ```
     * val workerClient = OkHttpClient.Builder()
     *     .callTimeout(0, TimeUnit.MILLISECONDS)       // no timeout for large downloads
     *     .readTimeout(5, TimeUnit.MINUTES)
     *     .addInterceptor(ChuckerInterceptor.Builder(context).build())
     *     .build()
     * OkHttpHttpTransport.setHttpClient(workerClient)
     * ```
     */
    @JvmStatic
    fun setHttpClient(client: OkHttpClient?) {
        clientRef.set(client)
    }

    /** Returns the currently installed custom client, or null if using default. */
    @JvmStatic
    fun getHttpClient(): OkHttpClient? = clientRef.get()

    // C-callback entry points (invoked by JNI; mirror Swift's
    // `cRequestSend` / `cRequestStream` / `cRequestResume` trampolines)

    /**
     * `request_send` vtable slot — blocking single-shot request. Invoked
     * from JNI via `CallStaticObjectMethod`. Returns a [HttpResponse] —
     * C++ unwraps the fields and marshals them into `rac_http_response_t`.
     *
     * @param method      HTTP method in uppercase ASCII ("GET"/"POST"/...).
     * @param url         Absolute HTTP/HTTPS URL.
     * @param headersFlat Flat `[k1, v1, k2, v2, ...]` header array
     *                    (matches the shape of `rac_http_header_kv_t[]`).
     * @param bodyBytes   Request body bytes, or null for GET/HEAD.
     * @param timeoutMs   Call timeout in ms (0 = use the shared client defaults).
     * @param followRedirects Whether OkHttp may follow HTTP/HTTPS redirects.
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
        followRedirects: Boolean = true,
    ): HttpResponse {
        return try {
            val request = buildRequest(method, url, headersFlat, bodyBytes, resumeFromByte = 0L)
            val clientForCall = resolveClient(timeoutMs, followRedirects)

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
     * Each chunk OkHttp reads off the wire is handed back via
     * [deliverChunkNative] — the C++ side translates the `long nativeCallback`
     * into the real `rac_http_body_chunk_fn` and forwards the bytes.
     *
     * Cancellation: when the native side signals "stop" by returning
     * `false` from `deliverChunkNative`, we call [okhttp3.Call.cancel] to
     * abort the TCP connection + short-circuit the Okio read loop.
     *
     * `body_bytes` in the returned [StreamResponse] is always null — the
     * body flows through the chunk callback instead. Headers + status are
     * populated for `rac_http_response_t` metadata on the C++ side.
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
        followRedirects: Boolean = true,
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
            followRedirects = followRedirects,
        )
    }

    /**
     * `request_resume` vtable slot — identical to [executeStreamingRequest]
     * but attaches a `Range: bytes=N-` header before dispatching. Mirrors
     * Swift's `cRequestResume`.
     *
     * Range-honored disclosure: when the caller asked for a partial
     * (`resumeFromByte > 0`) but the server answered with 200 (full file)
     * instead of 206, the C++ download manager needs to know so it can
     * truncate the destination before replaying bytes. libcurl surfaces
     * this by reporting the HTTP status directly; we mirror that and add
     * an explicit `X-RAC-Range-Honored` marker header to save the caller
     * a second status-code check (matches the Swift adapter's contract).
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
        followRedirects: Boolean = true,
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
            followRedirects = followRedirects,
        )
    }

    // Native bridge

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

    // Streaming core (shared between request_stream + request_resume)

    private fun streamInternal(
        method: String,
        url: String,
        headersFlat: Array<String>,
        bodyBytes: ByteArray?,
        timeoutMs: Long,
        nativeCallback: Long,
        nativeUserData: Long,
        resumeFromByte: Long,
        followRedirects: Boolean,
    ): StreamResponse {
        val streamId = streamIdCounter.incrementAndGet()
        // Pre-register the slot BEFORE building the Call so a cancelAllStreams()
        // that lands during startup observes this stream. Without this, the
        // newCall(request) → inFlightStreams[id] = call window let a cancel
        // miss the stream entirely and the request would still execute past
        // the teardown signal.
        val slot = StreamSlot()
        inFlightStreams[streamId] = slot
        return try {
            val request = buildRequest(method, url, headersFlat, bodyBytes, resumeFromByte)
            // Streaming downloads use the dedicated streaming client with a
            // 24-hour read timeout (multi-GB GGUFs over slow links can take
            // hours); the buffered client's 60s read / 600s call timeouts
            // would abort them mid-transfer.
            val clientForCall = resolveStreamingClient(timeoutMs, followRedirects)

            val call = clientForCall.newCall(request)
            // Publish the Call into the slot. If cancelAllStreams() landed
            // between slot pre-registration and now, `cancelRequested` is
            // already set; cancel the call immediately so execute() races
            // straight to the IOException → cancelled-response path.
            val cancelImmediately =
                synchronized(slot) {
                    slot.call = call
                    slot.cancelRequested
                }
            if (cancelImmediately) {
                call.cancel()
            }

            call.execute().use { resp ->
                // Range-honored disclosure: surface a synthetic header so the
                // C++ download manager can detect when the server ignored the
                // Range request and replayed the full file (200 instead of 206).
                val headerPairs = buildResponseHeaders(resp.headers, resumeFromByte, resp.code)
                val body =
                    resp.body
                        ?: return StreamResponse(
                            statusCode = resp.code,
                            headers = headerPairs,
                            errorMessage = null,
                            cancelled = false,
                        )

                // Resume accounting: when the server actually honored the
                // Range (206), Content-Length is only the *remaining* bytes
                // — add the resume offset so the chunk callback sees a
                // monotonic `total_written` that tracks absolute file
                // position. For 200 responses the server ignored the range
                // and is replaying the full file, so we leave the counter
                // at 0 (the caller will truncate).
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

    /**
     * Drains the response body chunk-by-chunk, forwarding each chunk to the
     * native callback. Returns `true` if the transfer was cancelled (either
     * by the callback returning false or by `Call.cancel()`).
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
                        // If the caller cancelled, OkHttp surfaces the abort
                        // as an IOException — treat that as a clean
                        // cancellation rather than a transport failure.
                        if (call.isCanceled()) {
                            cancelled = true
                            break
                        }
                        throw io
                    }
                if (n < 0) break
                if (n == 0) continue

                totalRead += n
                // Trim buffer to actual bytes read before handing off.
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

    // Helpers

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

        // Attach the Range header for resume requests. Matches Swift's
        // `RequestSnapshot.makeURLRequest(additionalRangeFromByte:)`.
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

    private fun resolveClient(timeoutMs: Long, followRedirects: Boolean): OkHttpClient {
        val base = clientRef.get() ?: defaultClient
        return base.newBuilder()
            .followRedirects(followRedirects)
            .followSslRedirects(followRedirects)
            .apply {
                if (timeoutMs > 0) callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            }
            .build()
    }

    /**
     * Streaming path uses [streamingClient] (24h read timeout) as the base.
     * If the caller supplied an explicit per-request `timeoutMs`, layer it
     * on as a `callTimeout` — that matches the request_send semantics and
     * still lets the read timeout cap individual stalled reads at 24h.
     */
    private fun resolveStreamingClient(timeoutMs: Long, followRedirects: Boolean): OkHttpClient {
        val base = streamingClient
        return base.newBuilder()
            .followRedirects(followRedirects)
            .followSslRedirects(followRedirects)
            .apply {
                if (timeoutMs > 0) callTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            }
            .build()
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
     * Mirrors the Swift adapter's `ResponseWriter` post-processing of
     * the headers on the streaming path.
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

    // Response DTOs

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
     *
     * [cancelled] is true iff the native side returned false from the chunk
     * callback and we aborted the transfer via `Call.cancel()`.
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
