package com.runanywhere.sdk.foundation

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * JVM implementation of time utilities
 */
actual fun currentTimeMillis(): Long = System.currentTimeMillis()

/**
 * Get current time as ISO8601 string
 * Matches iOS format exactly: "2025-10-25 23:24:53+00"
 */
actual fun currentTimeISO8601(): String {
    val sdf = SimpleDateFormat("yyyy-MM-dd HH:mm:ss'+00'", Locale.US)
    sdf.timeZone = TimeZone.getTimeZone("UTC")
    return sdf.format(Date())
}
