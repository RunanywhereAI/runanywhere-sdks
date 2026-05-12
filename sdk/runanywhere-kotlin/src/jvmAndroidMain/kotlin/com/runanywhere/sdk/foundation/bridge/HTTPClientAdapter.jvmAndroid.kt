/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTPClientAdapter.jvmAndroid.kt
 *
 * jvmAndroid actuals for the commonMain `HTTPClientAdapter` expect
 * declarations. Routes the two platform hooks
 * (`platformExecuteHttp` and `platformResolveAuthToken`) through the
 * JNI bridge — the rest of the adapter logic lives in commonMain.
 *
 * - `platformExecuteHttp` → `RunAnywhereBridge.racHttpRequestExecute`
 *   on `Dispatchers.IO` (the underlying JNI call is blocking).
 * - `platformResolveAuthToken` → `CppBridgeAuth.getValidToken()`, which
 *   internally re-issues the refresh round-trip when the in-memory
 *   token is expired.
 *
 * Mirrors Swift's `HTTPClientAdapter`'s use of a concurrent
 * `DispatchQueue` for the blocking `rac_http_request_send` call.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeAuth
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
    if (resp == null) {
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

internal actual suspend fun platformResolveAuthToken(): String? =
    withContext(Dispatchers.IO) {
        // `CppBridgeAuth.getValidToken` wraps `racAuthGetValidToken` and
        // re-issues the refresh round-trip when the in-memory token is
        // expired — mirrors Swift's `rac_auth_get_valid_token` +
        // `CppBridge.Auth.refreshToken` handshake.
        CppBridgeAuth.getValidToken()
    }
