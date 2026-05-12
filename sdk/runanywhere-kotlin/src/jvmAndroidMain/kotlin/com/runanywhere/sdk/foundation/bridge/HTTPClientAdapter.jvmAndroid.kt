/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTPClientAdapter.jvmAndroid.kt
 *
 * jvmAndroid actuals for the commonMain `HTTPClientAdapter` expect
 * declarations. Routes the five platform hooks
 * (`platformExecuteHttp`, `platformExecuteHttpUpsert`,
 *  `platformDefaultHeaders`, `platformParseAPIError`,
 *  `platformResolveAuthToken`) through the JNI bridge — the rest of
 * the adapter logic lives in commonMain.
 *
 * Mirrors Swift's `HTTPClientAdapter`'s use of a concurrent
 * `DispatchQueue` for the blocking `rac_http_request_send` call.
 *
 * Pre-thunk fallback: the three Swift-parity helpers
 * (`racHttpDefaultHeaders`, `racHttpRequestExecuteWithUpsert`,
 *  `racApiErrorFromResponse`) are declared on `RunAnywhereBridge` but
 * their `Java_*` C JNI thunks are not yet authored in
 * `runanywhere_commons_jni.cpp`. Each call site below catches
 * `UnsatisfiedLinkError` and falls back to either the inlined Kotlin
 * behavior or the non-upsert request path, so the adapter compiles and
 * runs even before the thunks land.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeAuth
import com.runanywhere.sdk.native.bridge.NativeHttpResponse
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal actual suspend fun platformExecuteHttp(
    method: String,
    url: String,
    headerKeys: Array<String>,
    headerValues: Array<String>,
    body: ByteArray?,
    timeoutMs: Int,
    followRedirects: Boolean,
): HttpExecutionResult = withContext(Dispatchers.IO) {
    val resp = RunAnywhereBridge.racHttpRequestExecute(
        method = method,
        url = url,
        headerKeys = headerKeys,
        headerValues = headerValues,
        body = body,
        timeoutMs = timeoutMs,
        followRedirects = followRedirects,
    )
    nativeHttpResponseToResult(resp)
}

internal actual suspend fun platformExecuteHttpUpsert(
    method: String,
    url: String,
    headerKeys: Array<String>,
    headerValues: Array<String>,
    body: ByteArray?,
    timeoutMs: Int,
    followRedirects: Boolean,
    onConflictField: String,
): HttpExecutionResult = withContext(Dispatchers.IO) {
    val resp: NativeHttpResponse? = try {
        RunAnywhereBridge.racHttpRequestExecuteWithUpsert(
            method = method,
            url = url,
            headerKeys = headerKeys,
            headerValues = headerValues,
            body = body,
            timeoutMs = timeoutMs,
            followRedirects = followRedirects,
            onConflictField = onConflictField,
        )
    } catch (_: UnsatisfiedLinkError) {
        // JNI thunk not yet bound — degrade gracefully to the non-upsert
        // path. The Prefer header rewrite happens commonMain-side in
        // `buildHeaders` until the C thunk lands.
        null
    }
    if (resp != null) {
        nativeHttpResponseToResult(resp)
    } else {
        // Fallback: emit the same request without the upsert flag. We
        // also need to apply Swift's pre-commons header rewrite so
        // Supabase still sees `resolution=merge-duplicates` on the
        // Prefer header.
        val (fbKeys, fbValues) = rewriteForUpsertFallback(headerKeys, headerValues)
        val fallback = RunAnywhereBridge.racHttpRequestExecute(
            method = method,
            url = url,
            headerKeys = fbKeys,
            headerValues = fbValues,
            body = body,
            timeoutMs = timeoutMs,
            followRedirects = followRedirects,
        )
        nativeHttpResponseToResult(fallback)
    }
}

internal actual fun platformDefaultHeaders(): List<Pair<String, String>>? {
    return try {
        val flat = RunAnywhereBridge.racHttpDefaultHeaders() ?: return null
        if (flat.size % 2 != 0) return null
        val out = ArrayList<Pair<String, String>>(flat.size / 2)
        var i = 0
        while (i < flat.size) {
            out.add(flat[i] to flat[i + 1])
            i += 2
        }
        out
    } catch (_: UnsatisfiedLinkError) {
        // JNI thunk not yet bound — caller falls back to inlined headers.
        null
    }
}

internal actual fun platformParseAPIError(
    statusCode: Int,
    body: String,
    url: String,
): ApiErrorInfo? {
    return try {
        val out = RunAnywhereBridge.racApiErrorFromResponse(statusCode, body, url) ?: return null
        ApiErrorInfo(
            message = out.getOrElse(0) { "" },
            code = out.getOrElse(1) { "" },
            requestUrl = out.getOrElse(2) { "" },
        )
    } catch (_: UnsatisfiedLinkError) {
        // JNI thunk not yet bound — caller falls back to "HTTP {status}".
        null
    }
}

internal actual suspend fun platformResolveAuthToken(): String? =
    withContext(Dispatchers.IO) {
        // `CppBridgeAuth.getValidToken` wraps `racAuthGetValidToken` and
        // re-issues the refresh round-trip when the in-memory token is
        // expired — mirrors Swift's `rac_auth_get_valid_token` +
        // `CppBridge.Auth.refreshToken` handshake.
        CppBridgeAuth.getValidToken()
    }

// ────────────────────────────────────────────────────────────────────────
// Private helpers
// ────────────────────────────────────────────────────────────────────────

private fun nativeHttpResponseToResult(resp: NativeHttpResponse?): HttpExecutionResult {
    return if (resp == null) {
        HttpExecutionResult(
            statusCode = 0,
            body = ByteArray(0),
            transportError = "native HTTP call returned null",
        )
    } else if (resp.errorMessage != null) {
        HttpExecutionResult(
            statusCode = resp.statusCode,
            body = resp.body,
            transportError = resp.errorMessage,
        )
    } else {
        HttpExecutionResult(
            statusCode = resp.statusCode,
            body = resp.body,
            transportError = null,
        )
    }
}

/**
 * Pre-thunk Supabase upsert fallback. When the commons-side
 * `rac_http_request_set_upsert_mode` JNI thunk is not yet bound we
 * replicate the Prefer-header rewrite here so the request still wears
 * the `resolution=merge-duplicates` policy expected by PostgREST. The
 * URL `?on_conflict={field}` query argument remains unset — full
 * compliance requires the C-side thunk to land.
 */
private fun rewriteForUpsertFallback(
    keys: Array<String>,
    values: Array<String>,
): Pair<Array<String>, Array<String>> {
    val outKeys = keys.copyOf().toMutableList()
    val outValues = values.copyOf().toMutableList()
    var preferIdx = -1
    for (i in outKeys.indices) {
        if (outKeys[i].equals("Prefer", ignoreCase = true)) {
            preferIdx = i
            break
        }
    }
    val upsertPrefer = "resolution=merge-duplicates,return=representation"
    if (preferIdx >= 0) {
        outValues[preferIdx] = upsertPrefer
    } else {
        outKeys.add("Prefer")
        outValues.add(upsertPrefer)
    }
    return outKeys.toTypedArray() to outValues.toTypedArray()
}
