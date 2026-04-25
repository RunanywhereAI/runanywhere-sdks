/*
 * CppBridge+Auth.kt — RunAnywhere SDK
 *
 * v2.1 quick-wins Item 4 / GAP 08 #2 — post T3.4 state.
 *
 * Before T3.4 this file was a ~150 LOC HTTP-transport adapter built on
 * HttpURLConnection that forwarded request/response bodies to the
 * matching rac_auth_* C ABI. T3.4 moves the HTTP transport into the
 * commons libcurl-backed `rac_http_client_*` ABI (exposed via
 * [RunAnywhereBridge.racHttpRequestExecute]). Kotlin now owns zero
 * network plumbing for auth — the whole round-trip (request build →
 * POST → response parse → state update) happens in native code.
 *
 * Public API surface unchanged — the call sites in CppBridge,
 * CppBridgeModelAssignment, CppBridgeTelemetry, and CppBridgeDevice
 * continue to compile.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Backend-issued auth response. Kept for the public API contract; the
 *  4 call sites only read `accessToken`. The actual parse + state
 *  application happens in C++ via rac_auth_handle_authenticate_response. */
@Serializable
data class AuthenticationResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("device_id")    val deviceId: String,
    @SerialName("expires_in")   val expiresIn: Int,
    @SerialName("organization_id") val organizationId: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("token_type")   val tokenType: String,
    @SerialName("user_id")      val userId: String? = null,
)

/**
 * Thin facade over the `rac_auth_*` C ABI. State, request-building,
 * response-parsing, refresh-window math, and HTTP transport all live
 * in native. This file only exists to preserve the public Kotlin API
 * used by the rest of the SDK.
 */
object CppBridgeAuth {
    private const val TAG = "CppBridge/Auth"
    private const val ENDPOINT_AUTHENTICATE = "/api/v1/auth/sdk/authenticate"
    private const val ENDPOINT_REFRESH      = "/api/v1/auth/sdk/refresh"
    private const val REQUEST_TIMEOUT_MS    = 30_000

    /** Initialize native auth state. Idempotent. */
    init { RunAnywhereBridge.racAuthInit() }

    val accessToken: String? get() = RunAnywhereBridge.racAuthGetAccessToken()

    val tokenNeedsRefresh: Boolean get() = RunAnywhereBridge.racAuthNeedsRefresh()

    val isAuthenticated: Boolean get() = RunAnywhereBridge.racAuthIsAuthenticated()

    /** Returns a valid access token, refreshing if needed. NULL if no auth state. */
    fun getValidToken(): String? {
        val current = RunAnywhereBridge.racAuthGetAccessToken() ?: return null
        if (!tokenNeedsRefresh) return current

        val baseUrl = activeBaseUrl ?: return current
        val body = RunAnywhereBridge.racAuthBuildRefreshRequest() ?: return null
        return try {
            val response = postJson(baseUrl + ENDPOINT_REFRESH, body)
            if (RunAnywhereBridge.racAuthHandleRefreshResponse(response) == 0) {
                RunAnywhereBridge.racAuthGetAccessToken()
            } else current
        } catch (_: Exception) { current }
    }

    /**
     * One-shot authenticate against the backend. MUST be called from a
     * background thread (the call site in CppBridge.kt already wraps it
     * in withContext(Dispatchers.IO)).
     */
    fun authenticate(
        apiKey: String,
        baseUrl: String,
        deviceId: String,
        platform: String = "android",
        sdkVersion: String = "0.1.0",
        environment: Int = 0,  // 0 = DEVELOPMENT
    ): AuthenticationResponse {
        activeBaseUrl = baseUrl
        val body = RunAnywhereBridge.racAuthBuildAuthenticateRequest(
            apiKey, baseUrl, deviceId, platform, sdkVersion, environment,
        ) ?: throw IllegalStateException("$TAG: rac_auth_build_authenticate_request returned null")
        val response = postJson(baseUrl + ENDPOINT_AUTHENTICATE, body)
        if (RunAnywhereBridge.racAuthHandleAuthenticateResponse(response) != 0) {
            throw RuntimeException("$TAG: rac_auth_handle_authenticate_response rejected the body")
        }
        return jsonParser.decodeFromString(AuthenticationResponse.serializer(), response)
    }

    /** Clear all auth state (logout). Delegates to native. */
    fun reset() {
        RunAnywhereBridge.racAuthReset()
        activeBaseUrl = null
    }

    @Volatile private var activeBaseUrl: String? = null

    private val jsonParser = kotlinx.serialization.json.Json {
        ignoreUnknownKeys = true; isLenient = true
    }

    /**
     * JSON POST via the native curl-backed HTTP client. Throws on any
     * transport error or non-2xx HTTP status; native response handlers
     * are always invoked with 2xx bodies only.
     */
    private fun postJson(url: String, body: String): String {
        val resp = RunAnywhereBridge.racHttpRequestExecute(
            method = "POST",
            url = url,
            headerKeys = arrayOf("Content-Type", "Accept"),
            headerValues = arrayOf("application/json", "application/json"),
            body = body.encodeToByteArray(),
            timeoutMs = REQUEST_TIMEOUT_MS,
            followRedirects = true,
        ) ?: throw RuntimeException("$TAG: native HTTP call returned null")

        if (resp.errorMessage != null) {
            throw RuntimeException("$TAG: $url transport error: ${resp.errorMessage}")
        }
        val text = resp.bodyAsString()
        if (!resp.isSuccess) {
            throw RuntimeException("$TAG: $url HTTP ${resp.statusCode}: $text")
        }
        return text
    }
}
