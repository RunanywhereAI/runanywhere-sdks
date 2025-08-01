package com.runanywhere.runanywhereai.utils

import java.util.Locale

/**
 * Format bytes to human readable string
 */
fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "$bytes B"

    val units = arrayOf("KB", "MB", "GB", "TB")
    var value = bytes.toDouble()
    var unitIndex = -1

    while (value >= 1024 && unitIndex < units.size - 1) {
        value /= 1024
        unitIndex++
    }

    return String.format(Locale.US, "%.1f %s", value, units[unitIndex])
}

/**
 * Format number with thousands separator
 */
fun formatNumber(number: Long): String {
    return String.format(Locale.US, "%,d", number)
}

/**
 * Format time duration in milliseconds to readable string
 */
fun formatDuration(milliseconds: Long): String {
    val seconds = milliseconds / 1000
    val minutes = seconds / 60
    val hours = minutes / 60

    return when {
        hours > 0 -> String.format(Locale.US, "%d:%02d:%02d", hours, minutes % 60, seconds % 60)
        minutes > 0 -> String.format(Locale.US, "%d:%02d", minutes, seconds % 60)
        else -> String.format(Locale.US, "%ds", seconds)
    }
}
