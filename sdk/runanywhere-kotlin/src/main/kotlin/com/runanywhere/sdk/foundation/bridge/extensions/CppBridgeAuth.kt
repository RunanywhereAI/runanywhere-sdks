/*
 * CppBridge+Auth.kt — RunAnywhere SDK
 *
 * This file was previously a ~150 LOC HTTP-transport adapter built on
 * HttpURLConnection that forwarded request/response bodies to the
 * matching rac_auth_* C ABI. The HTTP transport now lives in the
 * commons libcurl-backed `rac_http_client_*` ABI (exposed via
 * [RunAnywhereBridge.racHttpRequestExecute]). Kotlin now owns zero
 * network plumbing for auth — the whole round-trip (request build →
 * POST → response parse → state update) happens in native code.
 *
 * Public API surface unchanged — the call sites in CppBridge,
 * CppBridgeTelemetry, and CppBridgeDevice continue to compile.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import ai.runanywhere.proto.v1.ErrorCategory as ProtoErrorCategory
import ai.runanywhere.proto.v1.ErrorCode as ProtoErrorCode

/** Backend-issued auth response. Kept for the public API contract; the
 *  4 call sites only read `accessToken`. The actual parse + state
 *  application happens in C++ via rac_auth_handle_authenticate_response. */
@Serializable
data class AuthenticationResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("device_id") val deviceId: String,
    @SerialName("expires_in") val expiresIn: Int,
    @SerialName("organization_id") val organizationId: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("token_type") val tokenType: String,
    @SerialName("user_id") val userId: String? = null,
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
    private const val ENDPOINT_REFRESH = "/api/v1/auth/sdk/refresh"
    private const val REQUEST_TIMEOUT_MS = 30_000

    @Volatile private var initialized: Boolean = false

    /**
     * Initialize the native auth manager with a secure-storage vtable backed
     * by the platform adapter's secureGet/secureSet/secureDelete callbacks.
     *
     * Must be called AFTER [CppBridgePlatformAdapter.register] has wired up
     * the secure-storage delegate, otherwise rac_auth_save_tokens /
     * rac_auth_clear fall back to in-memory-only and tokens are lost across
     * process restarts. Idempotent.
     *
     * Called from [com.runanywhere.sdk.foundation.bridge.CppBridge.initialize]
     * during Phase 1.
     */
    fun initialize() {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            RunAnywhereBridge.racAuthInit()
            com.runanywhere.sdk.infrastructure.logging
                .SDKLogger(TAG)
                .info("Native auth manager initialized with secure storage vtable")
            initialized = true
        }
    }

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
            } else {
                current
            }
        } catch (_: Exception) {
            current
        }
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
        platform: String = SDKConstants.SDK_PLATFORM,
        sdkVersion: String = "0.1.0",
        environment: Int = 0, // 0 = DEVELOPMENT
    ): AuthenticationResponse {
        activeBaseUrl = baseUrl
        val body =
            RunAnywhereBridge.racAuthBuildAuthenticateRequest(
                apiKey,
                baseUrl,
                deviceId,
                platform,
                sdkVersion,
                environment,
            ) ?: throw IllegalStateException("$TAG: rac_auth_build_authenticate_request returned null")
        val response = postJson(baseUrl + ENDPOINT_AUTHENTICATE, body)
        if (RunAnywhereBridge.racAuthHandleAuthenticateResponse(response) != 0) {
            throw RuntimeException("$TAG: rac_auth_handle_authenticate_response rejected the body")
        }
        return jsonParser.decodeFromString(AuthenticationResponse.serializer(), response)
    }

    /**
     * Refresh the access token. Mirrors Swift's `CppBridge.Auth.refreshToken()`.
     *
     * Builds a refresh request JSON via native (reads refresh_token + device_id
     * from C++ auth state), POSTs it to the refresh endpoint, and hands the raw
     * response back to native for parse + state update.
     *
     * @throws SDKException with [ProtoErrorCode.ERROR_CODE_INVALID_API_KEY] when
     *   no refresh token is available, or
     *   [ProtoErrorCode.ERROR_CODE_AUTHENTICATION_FAILED] when the response
     *   handler rejects the body.
     */
    fun refreshToken() {
        val baseUrl =
            activeBaseUrl
                ?: throw SDKException.invalidConfiguration(
                    "$TAG: Token refresh skipped: no usable external config",
                )

        val body =
            RunAnywhereBridge.racAuthBuildRefreshRequest()
                ?: throw SDKException.make(
                    code = ProtoErrorCode.ERROR_CODE_INVALID_API_KEY,
                    message = "$TAG: No refresh token",
                    category = ProtoErrorCategory.ERROR_CATEGORY_AUTH,
                )

        val response = postJson(baseUrl + ENDPOINT_REFRESH, body)
        if (RunAnywhereBridge.racAuthHandleRefreshResponse(response) != 0) {
            throw SDKException.authenticationFailed(
                reason = "$TAG: rac_auth_handle_refresh_response rejected the body",
            )
        }
    }

    /**
     * Clear all auth state (logout). Delegates to native. Mirrors Swift's
     * `CppBridge.Auth.clearAuth()`.
     *
     * Wipes the in-memory auth state — and, because [initialize] wires up the
     * secure-storage vtable, also deletes the persisted tokens.
     */
    fun clearAuth() {
        RunAnywhereBridge.racAuthReset()
        activeBaseUrl = null
    }

    @Volatile private var activeBaseUrl: String? = null

    private val jsonParser =
        kotlinx.serialization.json.Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

    /**
     * JSON POST via the native curl-backed HTTP client. Throws on any
     * transport error or non-2xx HTTP status; native response handlers
     * are always invoked with 2xx bodies only.
     */
    private fun postJson(url: String, body: String): String {
        val resp =
            RunAnywhereBridge.racHttpRequestExecute(
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
