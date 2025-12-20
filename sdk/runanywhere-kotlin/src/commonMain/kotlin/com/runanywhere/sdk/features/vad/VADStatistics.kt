package com.runanywhere.sdk.features.vad

/**
 * Statistics for VAD debugging and monitoring.
 * Mirrors iOS VADStatistics struct exactly.
 *
 * These statistics are primarily used for debugging and monitoring
 * the energy-based VAD algorithm.
 */
data class VADStatistics(
    /** Current energy level */
    val current: Float,
    /** Energy threshold being used */
    val threshold: Float,
    /** Ambient noise level (from calibration) */
    val ambient: Float,
    /** Recent average energy level */
    val recentAvg: Float,
    /** Recent maximum energy level */
    val recentMax: Float,
) {
    /**
     * Formatted debug description matching iOS CustomStringConvertible
     */
    override fun toString(): String =
        """
        VADStatistics:
          Current: ${String.format("%.6f", current)}
          Threshold: ${String.format("%.6f", threshold)}
          Ambient: ${String.format("%.6f", ambient)}
          Recent Avg: ${String.format("%.6f", recentAvg)}
          Recent Max: ${String.format("%.6f", recentMax)}
        """.trimIndent()

    companion object {
        /**
         * Create empty/default statistics
         */
        fun empty(): VADStatistics =
            VADStatistics(
                current = 0f,
                threshold = 0f,
                ambient = 0f,
                recentAvg = 0f,
                recentMax = 0f,
            )
    }
}
