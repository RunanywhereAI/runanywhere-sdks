package com.runanywhere.sdk.utils

import kotlinx.serialization.Serializable

/**
 * Simple Instant replacement for avoiding kotlinx-datetime issues
 */
@Serializable
data class SimpleInstant(
    val millis: Long,
) {
    companion object {
        fun now(): SimpleInstant = SimpleInstant(getCurrentTimeMillis())
    }

    fun toEpochMilliseconds(): Long = millis
}

/**
 * Convert Long timestamp to SimpleInstant
 */
fun Long.toSimpleInstant(): SimpleInstant = SimpleInstant(this)
