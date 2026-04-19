/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Manages Sentry SDK initialization for crash reporting and error tracking.
 * Matches iOS SDK's SentryManager.swift.
 */

package com.runanywhere.sdk.foundation.logging

import com.runanywhere.sdk.foundation.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.utils.SDKConstants
import io.sentry.Breadcrumb
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.SentryOptions
import io.sentry.protocol.Message
import io.sentry.protocol.User

/**
 * Manages Sentry SDK initialization and configuration.
 * Provides centralized error tracking for the RunAnywhere SDK.
 */
object SentryManager {
    private const val TAG = "SentryManager"

    @Volatile
    private var _isInitialized: Boolean = false

    /**
     * Whether Sentry has been successfully initialized.
     */
    val isInitialized: Boolean
        get() = _isInitialized

    // =============================================================================
    // INITIALIZATION
    // =============================================================================

    /**
     * Initialize Sentry with the configured DSN.
     *
     * @param dsn Sentry DSN (if null, uses C++ config sentryDSN)
     * @param environment SDK environment for tagging events
     */
    fun initialize(
        dsn: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT,
    ) {
        if (_isInitialized) {
            return
        }

        // Use provided DSN or fallback to C++ config
        val sentryDSN = dsn ?: getSentryDsnFromConfig()

        if (sentryDSN.isNullOrEmpty() || sentryDSN == "YOUR_SENTRY_DSN_HERE") {
            SDKLogger(TAG).debug("Sentry DSN not configured. Crash reporting disabled.")
            return
        }

        try {
            Sentry.init { options: SentryOptions ->
                options.dsn = sentryDSN
                options.environment = environment.name.lowercase()
                options.isEnableAutoSessionTracking = true
                options.isAttachStacktrace = true
                options.tracesSampleRate = 0.0 // Disable performance tracing

                // Add SDK info to all events
                options.beforeSend =
                    SentryOptions.BeforeSendCallback { event, _ ->
                        event.setTag("sdk_name", "RunAnywhere")
                        event.setTag("sdk_version", SDKConstants.VERSION)
                        event
                    }
            }

            _isInitialized = true
            SDKLogger(TAG).info("Sentry initialized successfully")
        } catch (e: Exception) {
            SDKLogger(TAG).error("Failed to initialize Sentry: ${e.message}")
        }
    }

    /**
     * Get Sentry DSN from C++ dev config.
     */
    private fun getSentryDsnFromConfig(): String? {
        return try {
            RunAnywhereBridge.racDevConfigGetSentryDsn()
        } catch (e: Exception) {
            null
        }
    }

    // =============================================================================
    // DIRECT API (for advanced use cases)
    // =============================================================================

    /**
     * Capture an error directly with Sentry.
     *
     * @param error The error to capture
     * @param context Additional context as key-value pairs
     */
    fun captureError(error: Throwable, context: Map<String, Any?>? = null) {
        if (!_isInitialized) return

        Sentry.captureException(error) { scope ->
            context?.forEach { (key, value) ->
                scope.setExtra(key, value?.toString() ?: "null")
            }
        }
    }

    /**
     * Capture an error message directly with Sentry.
     *
     * @param message The error message
     * @param level Sentry level (defaults to ERROR)
     * @param context Additional context as key-value pairs
     */
    fun captureMessage(
        message: String,
        level: SentryLevel = SentryLevel.ERROR,
        context: Map<String, Any?>? = null,
    ) {
        if (!_isInitialized) return

        val event =
            SentryEvent().apply {
                this.level = level
                this.message =
                    Message().apply {
                        this.formatted = message
                    }
            }

        context?.forEach { (key, value) ->
            event.setExtra(key, value?.toString() ?: "null")
        }

        Sentry.captureEvent(event)
    }

    /**
     * Add a breadcrumb for context trail.
     *
     * @param category Category of the breadcrumb
     * @param message Message for the breadcrumb
     * @param level Log level
     * @param data Additional data
     */
    fun addBreadcrumb(
        category: String,
        message: String,
        level: SentryLevel = SentryLevel.INFO,
        data: Map<String, String>? = null,
    ) {
        if (!_isInitialized) return

        val breadcrumb =
            Breadcrumb().apply {
                this.category = category
                this.message = message
                this.level = level
                data?.forEach { (key, value) ->
                    this.setData(key, value)
                }
            }

        Sentry.addBreadcrumb(breadcrumb)
    }

    /**
     * Set user information for Sentry events.
     *
     * @param userId Unique user identifier
     * @param email User email (optional)
     * @param username Username (optional)
     */
    fun setUser(userId: String, email: String? = null, username: String? = null) {
        if (!_isInitialized) return

        val user =
            User().apply {
                this.id = userId
                this.email = email
                this.username = username
            }
        Sentry.setUser(user)
    }

    /**
     * Clear user information.
     */
    fun clearUser() {
        if (!_isInitialized) return
        Sentry.setUser(null)
    }

    /**
     * Flush pending events.
     *
     * @param timeoutMs Timeout in milliseconds
     */
    fun flush(timeoutMs: Long = 2000L) {
        if (!_isInitialized) return
        Sentry.flush(timeoutMs)
    }

    /**
     * Close Sentry SDK.
     */
    fun close() {
        if (!_isInitialized) return
        Sentry.close()
        _isInitialized = false
    }
}
