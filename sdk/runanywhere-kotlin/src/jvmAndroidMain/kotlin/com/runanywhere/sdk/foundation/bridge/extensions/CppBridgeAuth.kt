/*
 * CppBridge+Auth.kt — RunAnywhere SDK
 *
 * v2.1 quick-wins Item 4 / GAP 08 #2 closure. The pre-v2.1 implementation
 * (Phase 7 of the v2 close-out) was a "thin" 182-LOC HTTP/JSON/state shim
 * that still owned: 5 AtomicReference state fields, 60-second refresh
 * window math, JSON request body building, JSON response parsing.
 *
 * After v2.1 quick-wins Item 4 (commits bd7da766 + 13e79d3c), the
 * matching `rac_auth_*` C ABI is reachable from Kotlin via 16 JNI thunks
 * on RunAnywhereBridge. This file becomes a pure HTTP transport
 * adapter: state, request/response JSON, and refresh-window math live
 * in native C++ where they're shared with Swift / Dart / RN / Web.
 *
 * Public API surface unchanged — the 4 call sites in CppBridge.kt,
 * CppBridgeModelAssignment.kt, CppBridgeTelemetry.kt, CppBridgeDevice.kt
 * continue to compile.
 *
 * Refresh window is now sourced from rac_auth_needs_refresh() (60 sec
 * per the C ABI), not the old Kotlin REFRESH_WINDOW_MS constant. The
 * 5-min vs 60-sec drift bug is permanently fixed because Kotlin no
 * longer carries its own constant.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

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
 * Pure HTTP transport adapter for the rac_auth_* C ABI. State lives
 * in native; this file just runs the HTTP POST round-trips and hands
 * the response bodies back to native for parsing.
 */
object CppBridgeAuth {
    private const val TAG = "CppBridge/Auth"
    private const val ENDPOINT_AUTHENTICATE = "/api/v1/auth/sdk/authenticate"
    private const val ENDPOINT_REFRESH      = "/api/v1/auth/sdk/refresh"

    /** Initialize native auth state. Idempotent. */
    init { RunAnywhereBridge.racAuthInit() }

    val accessToken: String? get() = RunAnywhereBridge.racAuthGetAccessToken()

    val tokenNeedsRefresh: Boolean get() = RunAnywhereBridge.racAuthNeedsRefresh()

    val isAuthenticated: Boolean get() = RunAnywhereBridge.racAuthIsAuthenticated()

    /** Returns a valid access token, refreshing if needed. NULL if no auth state. */
    fun getValidToken(): String? {
        val current = RunAnywhereBridge.racAuthGetAccessToken() ?: return null
        if (!tokenNeedsRefresh) return current
        // Refresh path: native builds the refresh request body; we POST
        // it and hand the response back to native for parsing.
        val body = RunAnywhereBridge.racAuthBuildRefreshRequest() ?: return null
        // baseUrl is extracted from the configured environment in native;
        // we still need it here for the HTTP transport. The 4 call sites
        // pass it explicitly via authenticate() before getValidToken() is
        // first invoked, so we cache it in CppBridge.kt at init time.
        val baseUrl = activeBaseUrl ?: return current
        return try {
            val response = post(baseUrl + ENDPOINT_REFRESH, body, bearer = null)
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
        val response = post(baseUrl + ENDPOINT_AUTHENTICATE, body, bearer = null)
        if (RunAnywhereBridge.racAuthHandleAuthenticateResponse(response) != 0) {
            throw RuntimeException("$TAG: rac_auth_handle_authenticate_response rejected the body")
        }
        // Parse for the public-API contract — the kotlinx.serialization
        // path is preserved so existing callers that read parsed fields
        // (e.g. organizationId for telemetry) still work.
        return jsonParser.decodeFromString(AuthenticationResponse.serializer(), response)
    }

    /** Clear all auth state (logout). Delegates to native. */
    fun reset() {
        RunAnywhereBridge.racAuthReset()
        activeBaseUrl = null
    }

    // Private state we still hold in Kotlin: just the base URL for the
    // HTTP transport. Tokens, expiry, refresh-window math: all in C++.
    @Volatile private var activeBaseUrl: String? = null

    private val jsonParser = kotlinx.serialization.json.Json {
        ignoreUnknownKeys = true; isLenient = true
    }

    /** Minimal HTTP POST. The only Kotlin-side network code in this file. */
    private fun post(url: String, body: String, bearer: String?): String {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
            if (bearer != null) setRequestProperty("Authorization", "Bearer $bearer")
            doOutput = true
            connectTimeout = 30_000
            readTimeout = 30_000
        }
        try {
            OutputStreamWriter(conn.outputStream).use { it.write(body) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else (conn.errorStream ?: conn.inputStream)
            val text = BufferedReader(InputStreamReader(stream)).use { it.readText() }
            if (code !in 200..299) throw RuntimeException("$TAG: $url HTTP $code: $text")
            return text
        } finally {
            conn.disconnect()
        }
    }
}
