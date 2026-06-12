/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public logging controls mirroring Swift `RunAnywhere+Logging.swift`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.LogLevel
import ai.runanywhere.proto.v1.LoggingConfiguration
import com.runanywhere.sdk.infrastructure.logging.LogDestination
import com.runanywhere.sdk.infrastructure.logging.Logging
import com.runanywhere.sdk.public.RunAnywhere

/** Configure logging with a predefined proto-backed configuration. */
fun RunAnywhere.configureLogging(config: LoggingConfiguration) {
    Logging.configure(config)
}

/** Enable or disable local console logging. */
fun RunAnywhere.setLocalLoggingEnabled(enabled: Boolean) {
    Logging.setLocalLoggingEnabled(enabled)
}

/** Set the minimum log level for SDK logging. */
fun RunAnywhere.setLogLevel(level: LogLevel) {
    Logging.setMinLogLevel(level)
}

/** Enable or disable Sentry error tracking. */
fun RunAnywhere.setSentryLoggingEnabled(enabled: Boolean) {
    Logging.setSentryLoggingEnabled(enabled)
}

/** Add a custom log destination. */
fun RunAnywhere.addLogDestination(destination: LogDestination) {
    Logging.addDestinationSync(destination)
}

/** Enable verbose debugging mode. */
fun RunAnywhere.setDebugMode(enabled: Boolean) {
    setLogLevel(if (enabled) LogLevel.LOG_LEVEL_DEBUG else LogLevel.LOG_LEVEL_INFO)
    setLocalLoggingEnabled(enabled)
}

/** Force flush all pending logs to destinations. */
fun RunAnywhere.flushLogs() {
    Logging.flush()
}
