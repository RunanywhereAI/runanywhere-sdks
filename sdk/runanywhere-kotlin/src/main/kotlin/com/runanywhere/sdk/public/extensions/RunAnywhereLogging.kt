/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.extensions

/**
 * Log level for SDK logging.
 *
 * Cross-SDK contract: values match Swift `LogLevel` (debug=0, info=1, warning=2,
 * error=3, fault=4). Ordering is `larger value = more severe`, so the SDK
 * logger emits entries iff `level.value >= minLogLevel.value`.
 */
enum class LogLevel(
    val value: Int,
) {
    /** Debug level logging (most verbose) */
    DEBUG(0),

    /** Info level logging */
    INFO(1),

    /** Warning level logging */
    WARNING(2),

    /** Error level logging */
    ERROR(3),

    /** Fault level logging (critical system errors) */
    FAULT(4),
}
