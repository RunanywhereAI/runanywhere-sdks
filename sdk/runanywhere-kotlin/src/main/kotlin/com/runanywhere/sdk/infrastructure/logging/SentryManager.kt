/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Manages Sentry SDK initialization for crash reporting and error tracking.
 * Matches iOS SDK's SentryManager.swift.
 */

package com.runanywhere.sdk.infrastructure.logging

import com.runanywhere.sdk.foundation.constants.SDKConstants
import com.runanywhere.sdk.generated.convenience.wireString
import com.runanywhere.sdk.public.configuration.SDKEnvironment
import io.sentry.Sentry
import io.sentry.SentryOptions

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

    // Initialization

    /**
     * Initialize Sentry with the configured DSN.
     *
     * @param dsn Sentry DSN (if null, crash reporting stays disabled)
     * @param environment SDK environment for tagging events
     */
    fun initialize(
        dsn: String? = null,
        environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    ) {
        if (_isInitialized) {
            return
        }

        // DSN is supplied by the app/SDK config; it is no longer sourced from
        // C++ (commons holds no Sentry configuration).
        val sentryDSN = dsn

        if (sentryDSN.isNullOrEmpty() || sentryDSN == "YOUR_SENTRY_DSN_HERE") {
            SDKLogger(TAG).debug("Sentry DSN not configured. Crash reporting disabled.")
            return
        }

        try {
            Sentry.init { options: SentryOptions ->
                options.dsn = sentryDSN
                options.environment = environment.wireString
                options.isEnableAutoSessionTracking = true
                options.isAttachStacktrace = true
                options.tracesSampleRate = 0.0 // Disable performance tracing

                // Swift parity: matches enableCrashHandler / enableAutoBreadcrumbTracking /
                // enableAppHangTracking / appHangTimeoutInterval on iOS. The Java core
                // `io.sentry:sentry` lacks ANR + auto-breadcrumb-tracking flags — those live on
                // `SentryAndroidOptions` from `sentry-android-core`. Because this file is in the
                // `jvmAndroidMain` (shared JVM + Android) source set, we can't import the
                // Android-only type without breaking the JVM target. Reflect them in so they
                // apply on Android and no-op cleanly on JVM. ANR is Android-only;
                // `enableUncaughtExceptionHandler` (default true) covers JVM crash reporting.
                applyAndroidOnlyOptions(options)

                // Add SDK info to all events
                options.beforeSend =
                    SentryOptions.BeforeSendCallback { event, _ ->
                        event.setTag("sdk_name", "RunAnywhere")
                        event.setTag("sdk_version", SDKConstants.VERSION)
                        event
                    }
            }

            _isInitialized = true
            SDKLogger(TAG).debug("Sentry initialized successfully")
        } catch (e: Exception) {
            SDKLogger(TAG).error("Failed to initialize Sentry: ${e.message}")
        }
    }

    /**
     * Apply Sentry options that only exist on `SentryAndroidOptions` (sentry-android-core):
     *   - `enableAutoBreadcrumbTracking` — Swift's `options.enableAutoBreadcrumbTracking`
     *   - `anrEnabled` / `anrTimeoutIntervalMillis` — Swift's `enableAppHangTracking` +
     *     `appHangTimeoutInterval` (5000ms here vs Swift's 2000ms to align with Sentry-Android's
     *     ANR-detection default and reduce false positives).
     *
     * Reflection is used because this file is in the `jvmAndroidMain` shared source set and
     * cannot reference the Android-only `SentryAndroidOptions` type without breaking the JVM
     * target. On JVM the options object is plain `SentryOptions`, the setters are missing, and
     * the calls no-op silently — which is correct, since ANR detection is meaningless off-Android.
     */
    private fun applyAndroidOnlyOptions(options: SentryOptions) {
        invokeBooleanSetter(options, "setEnableAutoBreadcrumbTracking", true)
        invokeBooleanSetter(options, "setAnrEnabled", true)
        invokeLongSetter(options, "setAnrTimeoutIntervalMillis", 5_000L)
    }

    private fun invokeBooleanSetter(target: Any, methodName: String, value: Boolean) {
        try {
            val method = target.javaClass.getMethod(methodName, java.lang.Boolean.TYPE)
            method.invoke(target, value)
        } catch (_: NoSuchMethodException) {
            // Expected on JVM: this setter exists only on SentryAndroidOptions.
        } catch (_: Exception) {
            // Defensive: never let a reflection failure break SDK init.
        }
    }

    private fun invokeLongSetter(target: Any, methodName: String, value: Long) {
        try {
            val method = target.javaClass.getMethod(methodName, java.lang.Long.TYPE)
            method.invoke(target, value)
        } catch (_: NoSuchMethodException) {
            // Expected on JVM: this setter exists only on SentryAndroidOptions.
        } catch (_: Exception) {
            // Defensive: never let a reflection failure break SDK init.
        }
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
