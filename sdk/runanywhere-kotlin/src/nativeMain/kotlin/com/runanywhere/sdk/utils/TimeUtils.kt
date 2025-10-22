package com.runanywhere.sdk.utils

import kotlin.time.TimeSource

/**
 * Native implementation of time utilities
 */
actual fun getCurrentTimeMillis(): Long =
    TimeSource.Monotonic.markNow().elapsedNow().inWholeMilliseconds
