package com.runanywhere.sdk.features.llm.structuredoutput

import kotlin.system.getTimeMillis

/**
 * Get current time in milliseconds - Native implementation
 */
internal actual fun currentTimeMillis(): Long = getTimeMillis()
