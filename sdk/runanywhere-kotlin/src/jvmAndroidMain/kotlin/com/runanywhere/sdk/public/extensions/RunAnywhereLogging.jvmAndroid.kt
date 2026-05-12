/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for logging configuration.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.infrastructure.logging.Logging
import com.runanywhere.sdk.public.RunAnywhere

internal actual fun RunAnywhere.setLogLevelInternal(level: LogLevel) {
    Logging.setMinLogLevel(level)
}

actual fun RunAnywhere.flushLogs() {
    Logging.flush()
}
