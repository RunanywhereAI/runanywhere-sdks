/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTPClientAdapter.kt
 *
 * W2-6: thin Kotlin bridge over the canonical `rac_http_client_*` C ABI.
 * Mirrors Swift's `Foundation/Bridge/HTTPClientAdapter.swift` (336 LOC).
 *
 * All cross-platform HTTP policy lives in commons:
 *   - `rac_http_default_headers`         → canonical SDK header list
 *   - `rac_http_request_set_upsert_mode` → Supabase upsert semantics
 *   - `rac_api_error_from_response`      → HTTP-status → SDKException
 *
 * SDK-level HTTP requests (auth, device registration, telemetry) should
 * route through this adapter rather than calling `RunAnywhereBridge.
 * racHttpRequestExecute` directly. Migration of existing call sites
 * (CppBridgeAuth, CppBridgeTelemetry, CppBridgeDevice) is a follow-up
 * task — this file only CREATES the adapter scaffold.
 *
 * Concurrency: Swift uses `actor` isolation. Kotlin uses `Mutex` to
 * guard the `baseURL` / `apiKey` configuration state and runs the
 * blocking JNI `racHttpRequestExecute` call on `Dispatchers.IO`.
 *
 * Platform plumbing: the JNI calls to `racHttpRequestExecute` and
 * `racAuthGetValidToken` live in jvmAndroidMain (they only exist in
 * the JNI bridge). The `expect` declarations below give commonMain a
 * platform-neutral entry point. See
 * `HTTPClientAdapter.jvmAndroid.kt` for the actual implementation.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Outcome of a single platform HTTP request. Carries either:
 *   - the response body bytes plus a 2xx HTTP status (success path), or
 *   - a non-2xx HTTP status with the raw body for `mapAPIError` to read, or
 *   - a transport-level failure (DNS/TLS/timeout) flagged via [transportError].
 *
 * Kept as a plain data class so commonMain can interpret platform results
 * without depending on the JNI `NativeHttpResponse` type defined in
 * jvmAndroidMain.
 */
internal data class HttpExecutionResult(
    val statusCode: Int,
    val body: ByteArray,
    /** Non-null when the JNI transport itself failed (rc != RAC_SUCCESS). */
    val transportError: String? = null,
)

/**
 * Platform hook — execute one HTTP request via the C++ `rac_http_client_*`
 * vtable. The `actual` in jvmAndroidMain forwards to
 * `RunAnywhereBridge.racHttpRequestExecute` and runs on `Dispatchers.IO`.
 */
internal expect suspend fun platformExecuteHttp(
    method: String,
    url: String,
    headerKeys: Array<String>,
    headerValues: Array<String>,
    body: ByteArray?,
    timeoutMs: Int,
    followRedirects: Boolean,
): HttpExecutionResult

/**
 * Platform hook — resolve the currently-valid auth token, refreshing if
 * required. Returns `null` when no auth state is wired (e.g. development
 * mode) so the caller can fall back to the configured API key.
 *
 * Mirrors Swift's `rac_auth_get_valid_token` + `CppBridge.Auth.refreshToken`
 * handshake. The `actual` in jvmAndroidMain delegates to
 * `CppBridgeAuth.getValidToken()` which internally re-issues the refresh
 * round-trip when the in-memory token is expired.
 */
internal expect suspend fun platformResolveAuthToken(): String?

/**
 * HTTPClientAdapter — thin Kotlin bridge over `rac_http_client_*`.
 *
 * Singleton object (Swift uses an `actor`; Kotlin uses a `Mutex`-guarded
 * `object` to provide equivalent state isolation while keeping the API
 * surface symmetrical across SDKs).
 */
public object HTTPClientAdapter {

    private const val DEFAULT_TIMEOUT_MS: Int = 30_000

    /** Supabase device-registration endpoint marker (mirrors Swift's
     *  `RAC_ENDPOINT_DEV_DEVICE_REGISTER`). Path-substring match
     *  triggers the upsert-mode rewrite on the C side. */
    private const val DEV_DEVICE_REGISTER_MARKER: String = "/rest/v1/devices"

    private val logger = SDKLogger("HTTPClientAdapter")
    private val stateMutex = Mutex()

    @Volatile private var baseURL: String? = null

    @Volatile private var apiKey: String? = null

    // ────────────────────────────────────────────────────────────────────
    // Configuration
    // ────────────────────────────────────────────────────────────────────

    /**
     * Configure the adapter with a base URL and API key. Validates inputs
     * against the same `isUsableHTTPURL` / `isUsableCredential` rules used
     * by Swift's `CppBridge.DevConfig`. On invalid input the adapter is
     * left unconfigured rather than throwing.
     */
    public suspend fun configure(baseURL: String, apiKey: String) {
        val trimmedKey = apiKey.trim()
        stateMutex.withLock {
            if (!isUsableHTTPURL(baseURL) || !isUsableCredential(trimmedKey)) {
                this.baseURL = null
                this.apiKey = null
                logger.info("HTTP adapter not configured: no usable external config")
                return
            }
            this.baseURL = baseURL.trimEnd('/')
            this.apiKey = trimmedKey
            logger.info("HTTP adapter configured with base URL: $baseURL")
        }
    }

    /** True iff [configure] has been called with a non-null base URL. */
    public val isConfigured: Boolean
        get() = baseURL != null

    /**
     * True iff the adapter has both a usable HTTP URL and a usable API
     * credential, mirroring Swift's `hasUsableConfiguration`.
     */
    public val hasUsableConfiguration: Boolean
        get() {
            val url = baseURL ?: return false
            return isUsableHTTPURL(url) && isUsableCredential(apiKey)
        }

    // ────────────────────────────────────────────────────────────────────
    // Public request surface
    // ────────────────────────────────────────────────────────────────────

    /** Send a raw POST payload. Mirrors Swift `postRaw(_:_:requiresAuth:)`. */
    public suspend fun postRaw(
        path: String,
        payload: ByteArray,
        requiresAuth: Boolean,
    ): ByteArray = execute(method = "POST", path = path, body = payload, requiresAuth = requiresAuth)

    /** Send a raw GET. Mirrors Swift `getRaw(_:requiresAuth:)`. */
    public suspend fun getRaw(
        path: String,
        requiresAuth: Boolean,
    ): ByteArray = execute(method = "GET", path = path, body = null, requiresAuth = requiresAuth)

    /**
     * Post a JSON string. Mirrors Swift `post(_:json:requiresAuth:)` —
     * used by telemetry and auth flows that already have a JSON-serialized
     * body in hand.
     */
    public suspend fun post(
        path: String,
        json: String,
        requiresAuth: Boolean = false,
    ): ByteArray = postRaw(path, json.encodeToByteArray(), requiresAuth = requiresAuth)

    /**
     * Fetch an absolute URL without requiring adapter configuration or
     * auth. Intended for ancillary asset fetches (tokenizer blobs,
     * vocabularies) that live outside the SDK's configured base URL.
     *
     * Mirrors Swift's `static func fetchURL(_:timeoutMs:)`.
     */
    public suspend fun fetchURL(
        url: String,
        timeoutMs: Int = DEFAULT_TIMEOUT_MS,
    ): ByteArray {
        val result = platformExecuteHttp(
            method = "GET",
            url = url,
            headerKeys = arrayOf("X-Platform"),
            headerValues = arrayOf(SDK_PLATFORM),
            body = null,
            timeoutMs = timeoutMs,
            followRedirects = true,
        )
        return interpretResult(result, method = "GET", url = url)
    }

    // ────────────────────────────────────────────────────────────────────
    // Internal execution
    // ────────────────────────────────────────────────────────────────────

    private suspend fun execute(
        method: String,
        path: String,
        body: ByteArray?,
        requiresAuth: Boolean,
    ): ByteArray {
        val base = baseURL ?: throw SDKException.networkError("HTTP adapter not configured")
        val url = buildURL(base = base, path = path)
        val token = resolveToken(requiresAuth = requiresAuth)
        val isUpsert = path.contains(DEV_DEVICE_REGISTER_MARKER)

        val headers = buildHeaders(
            apiKey = apiKey,
            authToken = token.ifEmpty { null },
            upsert = isUpsert,
        )

        val result = platformExecuteHttp(
            method = method,
            url = url,
            headerKeys = headers.keys.toTypedArray(),
            headerValues = headers.values.toTypedArray(),
            body = body,
            timeoutMs = DEFAULT_TIMEOUT_MS,
            followRedirects = true,
        )
        return interpretResult(result, method = method, url = url)
    }

    /**
     * Resolve the auth token for a request. Mirrors Swift's
     * `rac_auth_get_valid_token` + refresh fallback:
     *  - When auth is not required → return the API key (may be empty).
     *  - When auth is required and a valid token is available → use it.
     *  - Otherwise fall back to the API key, throwing if none is set.
     */
    private suspend fun resolveToken(requiresAuth: Boolean): String {
        if (!requiresAuth) return apiKey ?: ""
        val token = platformResolveAuthToken()
        if (!token.isNullOrEmpty()) return token
        val key = apiKey
        if (!key.isNullOrEmpty()) return key
        throw SDKException.authenticationFailed(reason = "No valid authentication token")
    }

    /**
     * Translate a [HttpExecutionResult] into either the response body
     * bytes or a typed [SDKException]. Mirrors Swift's
     * `mapAPIError(statusCode:body:url:)` minus the
     * `rac_api_error_from_response` round-trip — that JNI thunk is
     * Swift-only today (commons exposes it; Kotlin will gain the
     * binding in a follow-up).
     */
    private fun interpretResult(
        result: HttpExecutionResult,
        method: String,
        url: String,
    ): ByteArray {
        if (result.transportError != null) {
            logger.error("HTTP transport failure for $method $url: ${result.transportError}")
            throw SDKException.networkError("HTTP transport error: ${result.transportError}")
        }
        if (result.statusCode in 200..299) return result.body
        val message = if (result.body.isEmpty()) {
            "HTTP error ${result.statusCode}"
        } else {
            "HTTP ${result.statusCode}: ${result.body.decodeToString()}"
        }
        logger.error("HTTP ${result.statusCode}: $method $url")
        throw when (result.statusCode) {
            401 -> SDKException.authenticationFailed(reason = message)
            403 -> SDKException.unauthorized(resource = url)
            in 500..599 -> SDKException.networkError(message)
            else -> SDKException.networkError(message)
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // Header / URL construction
    // ────────────────────────────────────────────────────────────────────

    /**
     * Build the per-request header map. Commons' canonical header list
     * (`rac_http_default_headers`) is not yet exposed to Kotlin — the
     * adapter inlines the policy until the JNI thunk lands, matching
     * what `CppBridgeAuth.postJson` and `CppBridgeTelemetry.sendTelemetry`
     * already do.
     */
    private fun buildHeaders(
        apiKey: String?,
        authToken: String?,
        upsert: Boolean,
    ): LinkedHashMap<String, String> {
        val headers = LinkedHashMap<String, String>(8)
        headers["Content-Type"] = "application/json"
        headers["Accept"] = "application/json"
        headers["X-Platform"] = SDK_PLATFORM
        if (apiKey != null) {
            headers["apikey"] = apiKey
            // Supabase PostgREST: include the inserted/updated row in
            // the response body. Mirrors Swift's identical line.
            headers["Prefer"] = "return=representation"
        }
        if (authToken != null) {
            headers["Authorization"] = "Bearer $authToken"
        }
        if (upsert) {
            // Supabase upsert mode. Swift hands this off to
            // `rac_http_request_set_upsert_mode` so commons rewrites the
            // URL + Prefer header. Kotlin doesn't have that thunk
            // wired, so we apply the same Prefer-header rewrite locally.
            headers["Prefer"] = "resolution=merge-duplicates,return=representation"
        }
        return headers
    }

    /**
     * Join `base` + `path`. Mirrors Swift's `buildURL(base:path:)`:
     *  - if `path` is already absolute, return it unchanged
     *  - otherwise concatenate, taking care to leave at most one `/`
     *    between the two parts
     */
    private fun buildURL(base: String, path: String): String {
        if (path.startsWith("http://") || path.startsWith("https://")) return path
        val trimmedBase = base.trimEnd('/')
        val normalizedPath = if (path.startsWith("/")) path else "/$path"
        return trimmedBase + normalizedPath
    }

    // ────────────────────────────────────────────────────────────────────
    // Local validators (mirror CppBridge.DevConfig in Swift)
    // ────────────────────────────────────────────────────────────────────

    private fun isUsableHTTPURL(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val trimmed = url.trim()
        return (trimmed.startsWith("http://") || trimmed.startsWith("https://")) &&
            trimmed.length > "https://".length
    }

    private fun isUsableCredential(credential: String?): Boolean {
        if (credential.isNullOrBlank()) return false
        return credential.trim().length >= MIN_CREDENTIAL_LENGTH
    }

    /**
     * `SDKConstants.platform` equivalent — Swift sets this to "iOS" /
     * "macOS" at compile time. Kotlin uses a single "android" value
     * because the JVM target is the desktop development surface only.
     * Mirrors the existing `CppBridgeAuth.authenticate` default.
     */
    private const val SDK_PLATFORM: String = "android"

    /** Minimum credential length matching commons'
     *  `RAC_MIN_CREDENTIAL_LEN` policy (8 bytes for an API key prefix). */
    private const val MIN_CREDENTIAL_LENGTH: Int = 8
}
