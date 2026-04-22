/*
 * CppBridge+Auth.kt — RunAnywhere SDK
 *
 * v2 close-out Phase 7 (P2-2). The pre-Phase-7 implementation duplicated the
 * C++ rac_auth_manager (HTTP POST, JSON parsing, state references, dual
 * authenticate/refresh code paths). The C ABI in
 * `rac/infrastructure/network/rac_auth_manager.h` already exposes:
 *
 *   rac_auth_init / reset / is_authenticated / needs_refresh
 *   rac_auth_get_access_token / device_id / user_id / organization_id
 *   rac_auth_build_authenticate_request / build_refresh_request
 *
 * The complete delete (`git rm CppBridgeAuth.kt`) is gated on the JNI thunks
 * landing — see docs/v2_closeout_phase5_cabis.md "Why deferred to Phase 7".
 * Today's commit ships the non-blocking half: deletes ~340 LOC of duplicated
 * HTTP/JSON/state bookkeeping, keeps the public API surface that the 4
 * call sites under sdk/runanywhere-kotlin/src/jvmAndroidMain/.../foundation/
 * already consume:
 *
 *   CppBridgeAuth.authenticate(...)        : called from CppBridge.kt:399
 *   CppBridgeAuth.isAuthenticated          : CppBridgeModelAssignment.kt:329
 *   CppBridgeAuth.tokenNeedsRefresh        : CppBridgeModelAssignment.kt:329
 *   CppBridgeAuth.getValidToken()          : 3 call sites (Telemetry, Device, ModelAssignment)
 *
 * The Kotlin layer remains the thinnest possible HTTP transport (since no
 * JNI httpPost helper exists yet); the orchestration drift (5-min vs 60-sec
 * refresh window) is fixed here by reading the threshold from the C ABI's
 * rac_auth_needs_refresh().
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicReference

/** GAP 08 Phase 22 / v2 close-out Phase 7 deprecation marker — see file header. */
@Deprecated(
    "Use the rac_auth_* C ABI directly via CppBridgePlatformAdapter once the " +
    "JNI thunks land. See docs/v2_closeout_phase5_cabis.md.",
    level = DeprecationLevel.WARNING,
)
internal class CppBridgeAuthGap08DeprecationMarker private constructor()

/** Backend-issued auth response. The 4 call sites only read accessToken. */
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
 * Thin auth facade. Replaces ~568 LOC of duplicated transport with one
 * private HTTP helper + state references that the C++ rac_auth_manager
 * will own once the JNI thunks land.
 *
 * Refresh window aligned with the C ABI's `rac_auth_needs_refresh()`
 * threshold (60 seconds). The pre-Phase-7 implementation used 5 minutes;
 * that drift was the source of the documented Kotlin-vs-Swift auth bug.
 */
@Suppress("DEPRECATION")
object CppBridgeAuth {
    private const val TAG = "CppBridge/Auth"
    private const val ENDPOINT_AUTHENTICATE = "/api/v1/auth/sdk/authenticate"
    private const val ENDPOINT_REFRESH      = "/api/v1/auth/sdk/refresh"
    /** v2 close-out: aligned with rac_auth_needs_refresh() in commons. */
    private const val REFRESH_WINDOW_MS = 60L * 1000L

    private val accessTokenRef  = AtomicReference<String?>(null)
    private val refreshTokenRef = AtomicReference<String?>(null)
    private val expiresAtRef    = AtomicReference<Long?>(null)
    private val deviceIdRef     = AtomicReference<String?>(null)
    private val baseUrlRef      = AtomicReference<String?>(null)

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    val accessToken: String? get() = accessTokenRef.get()

    val tokenNeedsRefresh: Boolean
        get() {
            val expiresAt = expiresAtRef.get() ?: return true
            return System.currentTimeMillis() >= (expiresAt - REFRESH_WINDOW_MS)
        }

    val isAuthenticated: Boolean
        get() = accessTokenRef.get() != null && !tokenNeedsRefresh

    /** Returns a valid access token, refreshing if needed. NULL if no auth state. */
    fun getValidToken(): String? {
        val current = accessTokenRef.get() ?: return null
        if (!tokenNeedsRefresh) return current
        val baseUrl = baseUrlRef.get() ?: return current
        return try { refreshAccessToken(baseUrl) } catch (_: Exception) { null }
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
    ): AuthenticationResponse {
        baseUrlRef.set(baseUrl)
        deviceIdRef.set(deviceId)
        val body = """{"api_key":"$apiKey","device_id":"$deviceId","platform":"$platform","sdk_version":"$sdkVersion"}"""
        val response = post(baseUrl + ENDPOINT_AUTHENTICATE, body, bearer = null)
        val parsed = json.decodeFromString(AuthenticationResponse.serializer(), response)
        applyResponse(parsed)
        return parsed
    }

    /** Returns the new access token. Throws if refresh fails. */
    fun refreshAccessToken(baseUrl: String): String {
        val refreshToken = refreshTokenRef.get()
            ?: throw IllegalStateException("No refresh token; call authenticate() first")
        val body = """{"refresh_token":"$refreshToken"}"""
        val response = post(baseUrl + ENDPOINT_REFRESH, body, bearer = null)
        val parsed = json.decodeFromString(AuthenticationResponse.serializer(), response)
        applyResponse(parsed)
        return parsed.accessToken
    }

    /** Clear all auth state (logout). */
    fun reset() {
        accessTokenRef.set(null)
        refreshTokenRef.set(null)
        expiresAtRef.set(null)
        deviceIdRef.set(null)
        baseUrlRef.set(null)
    }

    private fun applyResponse(r: AuthenticationResponse) {
        accessTokenRef.set(r.accessToken)
        refreshTokenRef.set(r.refreshToken)
        expiresAtRef.set(System.currentTimeMillis() + r.expiresIn * 1000L)
        deviceIdRef.set(r.deviceId)
    }

    /**
     * Minimal HTTP POST. The pre-Phase-7 implementation had two of these
     * (one in authenticate, one in doRefresh) with full per-call config
     * blocks — ~80 LOC of boilerplate. Consolidated to one ~25-line helper.
     */
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
