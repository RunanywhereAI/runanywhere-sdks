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
 * Upsert and API-error parsing are implemented Kotlin-side: the commons
 * C API does not expose an `rac_http_request_execute_with_upsert`
 * variant, and `rac_api_error_from_response` is internal-only
 * (non-RAC_API) and not exported in `RACommons.exports`. The Prefer-
 * header upsert rewrite happens here in [rewriteForUpsertFallback], and
 * 4xx/5xx parsing falls back to the caller's generic `"HTTP {status}"`
 * formatter.
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
): HttpExecutionResult =
    withContext(Dispatchers.IO) {
        val resp =
            RunAnywhereBridge.racHttpRequestExecute(
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
): HttpExecutionResult =
    withContext(Dispatchers.IO) {
        // The commons C API does not expose an upsert-mode HTTP variant, so
        // the upsert request is emitted via the standard execute path with
        // a Kotlin-side Prefer-header rewrite to advertise the Supabase
        // `resolution=merge-duplicates` policy expected by PostgREST. The
        // `onConflictField` is informational only at this layer; the
        // caller is responsible for appending any `?on_conflict={field}`
        // URL query argument.
        val (rewrittenKeys, rewrittenValues) = rewriteForUpsertFallback(headerKeys, headerValues)
        val resp =
            RunAnywhereBridge.racHttpRequestExecute(
                method = method,
                url = url,
                headerKeys = rewrittenKeys,
                headerValues = rewrittenValues,
                body = body,
                timeoutMs = timeoutMs,
                followRedirects = followRedirects,
            )
        nativeHttpResponseToResult(resp)
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
    @Suppress("UNUSED_PARAMETER") statusCode: Int,
    @Suppress("UNUSED_PARAMETER") body: String,
    @Suppress("UNUSED_PARAMETER") url: String,
): ApiErrorInfo? {
    // `rac_api_error_from_response` is internal-only in commons (non-RAC_API
    // and not exported in RACommons.exports), so there is no JNI thunk to
    // call. Returning null hands control back to the caller, which formats
    // a generic `"HTTP {status}"` message.
    return null
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
 * Kotlin-side Supabase upsert rewrite. Commons does not expose an
 * upsert-mode HTTP variant, so the Prefer header is rewritten here to
 * advertise the `resolution=merge-duplicates` policy expected by
 * PostgREST. The URL `?on_conflict={field}` query argument is not
 * appended at this layer — the caller owns URL construction.
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
