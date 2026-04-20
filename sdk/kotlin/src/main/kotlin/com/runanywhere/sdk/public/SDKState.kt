// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

/**
 * SDK-wide state: init, environment, API key, auth tokens, device
 * registration. Wraps ra_state_* / ra_init C ABI via JNI.
 */
object SDKState {

    enum class Environment(val raw: Int) {
        DEVELOPMENT(0), STAGING(1), PRODUCTION(2);
        companion object { fun of(raw: Int): Environment =
            values().firstOrNull { it.raw == raw } ?: PRODUCTION }
    }

    enum class LogLevel(val raw: Int) {
        TRACE(0), DEBUG(1), INFO(2), WARN(3), ERROR(4), FATAL(5)
    }

    data class Auth(
        val accessToken: String,
        val refreshToken: String = "",
        val expiresAt: Long = 0,
        val userId: String = "",
        val organizationId: String = "",
        val deviceId: String = "",
    )

    /** Initializes SDK. Registers env, API key, base URL, device ID. */
    @JvmStatic
    @JvmOverloads
    fun initialize(
        apiKey: String,
        environment: Environment = Environment.PRODUCTION,
        baseUrl: String = "",
        deviceId: String = "",
        logLevel: LogLevel = LogLevel.INFO,
    ) {
        require(NativeLibrary.isLoaded) { "racommons_core not loaded" }
        nativeSetLogLevel(logLevel.raw)
        val rc = nativeInitialize(environment.raw, apiKey, baseUrl, deviceId)
        if (rc != 0) throw RunAnywhereException(rc, "ra_state_initialize failed")
    }

    @JvmStatic val isInitialized: Boolean
        get() = NativeLibrary.isLoaded && nativeIsInitialized()

    @JvmStatic val environment: Environment
        get() = Environment.of(nativeGetEnvironment())
    @JvmStatic val baseUrl:   String get() = nativeGetBaseUrl()
    @JvmStatic val apiKey:    String get() = nativeGetApiKey()
    @JvmStatic val deviceId:  String get() = nativeGetDeviceId()

    @JvmStatic fun reset() { nativeReset() }

    @JvmStatic fun setAuth(auth: Auth) {
        val rc = nativeSetAuth(auth.accessToken, auth.refreshToken,
                                auth.expiresAt, auth.userId,
                                auth.organizationId, auth.deviceId)
        if (rc != 0) throw RunAnywhereException(rc, "ra_state_set_auth failed")
    }

    @JvmStatic val accessToken:    String get() = nativeGetAccessToken()
    @JvmStatic val refreshToken:   String get() = nativeGetRefreshToken()
    @JvmStatic val userId:         String get() = nativeGetUserId()
    @JvmStatic val organizationId: String get() = nativeGetOrganizationId()

    @JvmStatic val isAuthenticated: Boolean get() = nativeIsAuthenticated()

    @JvmStatic
    @JvmOverloads
    fun tokenNeedsRefresh(horizonSeconds: Int = 60): Boolean =
        nativeTokenNeedsRefresh(horizonSeconds)

    @JvmStatic val tokenExpiresAt: Long get() = nativeGetTokenExpiresAt()
    @JvmStatic fun clearAuth() { nativeClearAuth() }

    @JvmStatic val isDeviceRegistered: Boolean get() = nativeIsDeviceRegistered()
    @JvmStatic fun setDeviceRegistered(registered: Boolean) {
        nativeSetDeviceRegistered(registered)
    }

    @JvmStatic fun validateApiKey(key: String): Boolean = nativeValidateApiKey(key)
    @JvmStatic fun validateBaseUrl(url: String): Boolean = nativeValidateBaseUrl(url)

    @JvmStatic private external fun nativeInitialize(env: Int, apiKey: String,
                                                        baseUrl: String, deviceId: String): Int
    @JvmStatic private external fun nativeIsInitialized(): Boolean
    @JvmStatic private external fun nativeReset()
    @JvmStatic private external fun nativeGetEnvironment(): Int
    @JvmStatic private external fun nativeGetBaseUrl(): String
    @JvmStatic private external fun nativeGetApiKey(): String
    @JvmStatic private external fun nativeGetDeviceId(): String
    @JvmStatic private external fun nativeSetAuth(access: String, refresh: String,
                                                     expires: Long, userId: String,
                                                     orgId: String, deviceId: String): Int
    @JvmStatic private external fun nativeGetAccessToken(): String
    @JvmStatic private external fun nativeGetRefreshToken(): String
    @JvmStatic private external fun nativeGetUserId(): String
    @JvmStatic private external fun nativeGetOrganizationId(): String
    @JvmStatic private external fun nativeIsAuthenticated(): Boolean
    @JvmStatic private external fun nativeTokenNeedsRefresh(horizon: Int): Boolean
    @JvmStatic private external fun nativeGetTokenExpiresAt(): Long
    @JvmStatic private external fun nativeClearAuth()
    @JvmStatic private external fun nativeIsDeviceRegistered(): Boolean
    @JvmStatic private external fun nativeSetDeviceRegistered(r: Boolean)
    @JvmStatic private external fun nativeValidateApiKey(key: String): Boolean
    @JvmStatic private external fun nativeValidateBaseUrl(url: String): Boolean
    @JvmStatic private external fun nativeSetLogLevel(level: Int)
}
