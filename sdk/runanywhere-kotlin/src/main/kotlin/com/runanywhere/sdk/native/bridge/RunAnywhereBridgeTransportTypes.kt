/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.native.bridge

/**
 * Listener for native HTTP download progress. Invoked from the worker
 * thread that called `RunAnywhereBridge.racHttpDownloadExecute(...)`
 * on every libcurl chunk.
 *
 * Kept as a top-level type in this package so the
 * JNI `FindClass(..., "onProgress", "(JJ)Z")` contract stays stable while
 * RunAnywhereBridge retains the external function declarations.
 *
 * Return `false` to cancel the download — the native runner will
 * abort libcurl, close the partial file, and return
 * `RAC_HTTP_DL_CANCELLED`.
 */
fun interface NativeDownloadProgressListener {
    fun onProgress(bytesWritten: Long, totalBytes: Long): Boolean
}

/**
 * Listener for native proto-byte callbacks. The byte array is an owned copy of
 * the native callback payload and is safe to decode or dispatch asynchronously.
 */
fun interface NativeProtoProgressListener {
    fun onProgress(progressBytes: ByteArray): Boolean
}

/**
 * Synchronous tool-execute callback invoked by
 * [RunAnywhereBridge.racToolCallingRunLoopWithHandleAndCbProto] from the
 * thread that called it. Receives a serialized `runanywhere.v1.ToolCall` and
 * MUST return a serialized `runanywhere.v1.ToolResult`. Mirrors Swift's
 * `toolExecuteTrampoline` — the C run loop blocks on this call until the
 * result is returned.
 */
fun interface NativeToolExecuteListener {
    fun executeToolCall(toolCallBytes: ByteArray): ByteArray
}

/**
 * Synchronous handle-publication callback invoked by
 * [RunAnywhereBridge.racToolCallingRunLoopWithHandleAndCbProto] the moment
 * the cancellable run-loop handle is minted (before the first generate
 * iteration). Lets the Kotlin caller route the handle into a thread-safe sink
 * (e.g. `CompletableDeferred`) so a cancel coroutine can fan a cancel into
 * [RunAnywhereBridge.racToolCallingRunLoopCancelProto]. Mirrors Swift's
 * `HandleBox` publication and RN's `onHandle` JS callback.
 */
fun interface NativeRunLoopHandleListener {
    fun onHandlePublished(runLoopHandle: Long)
}

/**
 * Response descriptor returned by [RunAnywhereBridge.racHttpRequestExecute].
 *
 * Fields are `@JvmField` so the JNI layer can construct this object via a
 * single reflective `NewObject(...)` call with a matching
 * `(I[B[Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)V` signature.
 *
 * The `headerKeys` / `headerValues` arrays are parallel: `headerKeys[i]` pairs
 * with `headerValues[i]`. Empty when the server sent no headers.
 *
 * On transport-level failure (DNS/connect/TLS/timeout) [statusCode] is `-1`
 * and [errorMessage] is non-null. On HTTP-level 4xx/5xx responses,
 * [statusCode] reflects the server status and [errorMessage] stays null.
 */
class NativeHttpResponse(
    @JvmField val statusCode: Int,
    @JvmField val body: ByteArray,
    @JvmField val headerKeys: Array<String>,
    @JvmField val headerValues: Array<String>,
    @JvmField val errorMessage: String?,
) {
    /** True when the native call completed and the HTTP status is 2xx. */
    val isSuccess: Boolean get() = errorMessage == null && statusCode in 200..299

    /** Returns the response body decoded as UTF-8 (empty string on empty body). */
    fun bodyAsString(): String = if (body.isEmpty()) "" else body.decodeToString()

    /** Lookup helper; case-insensitive per RFC 7230. Returns null if not present. */
    fun header(name: String): String? {
        for (i in headerKeys.indices) {
            if (headerKeys[i].equals(name, ignoreCase = true)) return headerValues[i]
        }
        return null
    }

    /** Materialize headers as a map — O(n) allocation, use sparingly. */
    fun headersAsMap(): Map<String, String> =
        headerKeys.indices.associate { headerKeys[it] to headerValues[it] }
}
