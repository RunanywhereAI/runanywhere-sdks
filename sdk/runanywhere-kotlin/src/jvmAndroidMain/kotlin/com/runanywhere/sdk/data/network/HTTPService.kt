/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * HTTP Service - mirrors iOS HTTPService.swift
 * Centralized HTTP transport layer for all SDK network operations.
 */

package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.utils.SDKConstants
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * HTTP Service - Core network implementation
 * Centralized HTTP transport layer matching iOS HTTPService.swift
 *
 * All SDK network requests go through this service, which provides:
 * - Base URL configuration
 * - API key management
 * - Default headers (SDK version, platform info)
 * - Token resolution for authentication
 * - UPSERT support for device registration
 */
object HTTPService : NetworkService {

    private val logger = SDKLogger("HTTPService")

    // MARK: - Configuration

    @Volatile
    private var baseURL: String? = null

    @Volatile
    private var apiKey: String? = null

    // MARK: - Default Headers

    private fun getDefaultHeaders(): Map<String, String> {
        return mapOf(
            "Content-Type" to "application/json",
            "Accept" to "application/json",
            "X-SDK-Client" to "RunAnywhereSDK",
            "X-SDK-Version" to SDKConstants.SDK_VERSION,
            "X-Platform" to SDKConstants.platform
        )
    }

    // MARK: - Configuration Methods

    /**
     * Configure HTTP service with base URL and API key.
     * Mirrors Swift: HTTPService.shared.configure(baseURL:apiKey:)
     */
    fun configure(baseURL: String, apiKey: String) {
        this.baseURL = baseURL.trimEnd('/')
        this.apiKey = apiKey

        logger.info("HTTP service configured with base URL: ${extractHost(baseURL)}")
    }

    /**
     * Check if HTTP is configured
     */
    val isConfigured: Boolean
        get() = baseURL != null

    /**
     * Current base URL
     */
    val currentBaseURL: String?
        get() = baseURL

    /**
     * Current API key
     */
    val currentApiKey: String?
        get() = apiKey

    private fun extractHost(url: String): String {
        return try {
            URL(url).host
        } catch (e: Exception) {
            "unknown"
        }
    }

    // MARK: - NetworkService Protocol

    override suspend fun <T : Any, R : Any> post(
        endpoint: APIEndpoint,
        payload: T,
        requiresAuth: Boolean
    ): R {
        throw UnsupportedOperationException("Use postRaw for raw HTTP operations")
    }

    override suspend fun <R : Any> get(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): R {
        throw UnsupportedOperationException("Use getRaw for raw HTTP operations")
    }

    override suspend fun postRaw(
        endpoint: APIEndpoint,
        payload: ByteArray,
        requiresAuth: Boolean
    ): ByteArray {
        return postRaw(endpoint.path, payload, requiresAuth)
    }

    override suspend fun getRaw(
        endpoint: APIEndpoint,
        requiresAuth: Boolean
    ): ByteArray {
        return getRaw(endpoint.path, requiresAuth)
    }

    // MARK: - Raw HTTP Methods (mirroring Swift HTTPService)

    /**
     * POST request with raw payload
     * Mirrors Swift: HTTPService.postRaw(_:_:requiresAuth:)
     */
    suspend fun postRaw(
        path: String,
        payload: ByteArray,
        requiresAuth: Boolean = false,
        additionalHeaders: Map<String, String> = emptyMap()
    ): ByteArray = withContext(Dispatchers.IO) {
        val baseURL = this@HTTPService.baseURL
            ?: throw IllegalStateException("HTTP service not configured. Call configure() first.")

        val url = buildURL(baseURL, path)
        executeRequest(url, "POST", payload, requiresAuth, additionalHeaders)
    }

    /**
     * POST request with JSON string body
     * Mirrors Swift: HTTPService.post(_:json:requiresAuth:)
     */
    suspend fun post(
        path: String,
        json: String,
        requiresAuth: Boolean = false
    ): ByteArray {
        return postRaw(path, json.toByteArray(Charsets.UTF_8), requiresAuth)
    }

    /**
     * GET request with raw response
     * Mirrors Swift: HTTPService.getRaw(_:requiresAuth:)
     */
    suspend fun getRaw(
        path: String,
        requiresAuth: Boolean = false
    ): ByteArray = withContext(Dispatchers.IO) {
        val baseURL = this@HTTPService.baseURL
            ?: throw IllegalStateException("HTTP service not configured. Call configure() first.")

        val url = buildURL(baseURL, path)
        executeRequest(url, "GET", null, requiresAuth, emptyMap())
    }

    /**
     * DELETE request
     * Mirrors Swift: HTTPService.delete(_:requiresAuth:)
     */
    suspend fun delete(
        path: String,
        requiresAuth: Boolean = true
    ): ByteArray = withContext(Dispatchers.IO) {
        val baseURL = this@HTTPService.baseURL
            ?: throw IllegalStateException("HTTP service not configured. Call configure() first.")

        val url = buildURL(baseURL, path)
        executeRequest(url, "DELETE", null, requiresAuth, emptyMap())
    }

    // MARK: - Helper Methods

    private fun buildURL(base: String, path: String): String {
        val cleanPath = if (path.startsWith("/")) path else "/$path"
        return "$base$cleanPath"
    }

    private fun resolveToken(requiresAuth: Boolean): String {
        if (!requiresAuth) return ""

        // Fall back to API key as Bearer token (like Swift HTTPService.resolveToken)
        return apiKey ?: ""
    }

    private fun executeRequest(
        url: String,
        method: String,
        body: ByteArray?,
        requiresAuth: Boolean,
        additionalHeaders: Map<String, String>
    ): ByteArray {
        var connection: HttpURLConnection? = null

        try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = method
                connectTimeout = 30_000
                readTimeout = 30_000
                doInput = true
            }

            // Set default headers
            for ((key, value) in getDefaultHeaders()) {
                connection.setRequestProperty(key, value)
            }

            // Set API key header (Supabase-style)
            apiKey?.let { key ->
                connection.setRequestProperty("apikey", key)
            }

            // Set additional headers
            for ((key, value) in additionalHeaders) {
                connection.setRequestProperty(key, value)
            }

            // Add authorization header
            val token = resolveToken(requiresAuth)
            if (token.isNotEmpty()) {
                connection.setRequestProperty("Authorization", "Bearer $token")
            }

            // Write body if present
            if (body != null && method != "GET" && method != "HEAD") {
                connection.doOutput = true
                connection.outputStream.use { output ->
                    output.write(body)
                    output.flush()
                }
            }

            // Get response
            val statusCode = connection.responseCode

            // Handle device registration UPSERT (409 is OK for existing devices)
            val isDeviceRegistration = url.contains("/rest/v1/sdk_devices")
            val isSuccess = statusCode in 200..299 || (isDeviceRegistration && statusCode == 409)

            if (!isSuccess) {
                val errorBody = connection.errorStream?.use { stream ->
                    BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).readText()
                } ?: ""
                logger.error("HTTP $statusCode: $url - $errorBody")
                throw NetworkException(statusCode, "HTTP $statusCode: $errorBody")
            }

            // Log 409 as info for device registration
            if (isDeviceRegistration && statusCode == 409) {
                logger.info("Device already registered (409) - treating as success")
            }

            // Read response body
            val inputStream = if (statusCode in 200..299) {
                connection.inputStream
            } else {
                connection.errorStream
            }

            return inputStream?.use { stream ->
                stream.readBytes()
            } ?: ByteArray(0)

        } finally {
            connection?.disconnect()
        }
    }

    // MARK: - Reset (for testing)

    /**
     * Reset configuration (for testing)
     */
    fun reset() {
        baseURL = null
        apiKey = null
    }
}

/**
 * Network exception with status code
 */
class NetworkException(
    val statusCode: Int,
    message: String
) : Exception(message)

