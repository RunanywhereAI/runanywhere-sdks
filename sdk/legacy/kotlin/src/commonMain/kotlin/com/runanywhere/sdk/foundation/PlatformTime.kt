package com.runanywhere.sdk.foundation

/**
 * Platform-specific time utilities
 */
expect fun currentTimeMillis(): Long

/**
 * Get current time as ISO8601 string
 */
expect fun currentTimeISO8601(): String
