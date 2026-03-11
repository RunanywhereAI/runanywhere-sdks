package com.runanywhere.runanywhereai.models

import androidx.compose.runtime.Immutable
import kotlinx.serialization.Serializable

@Serializable
@Immutable
data class MessageAnalytics(
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    /** Total generation time in milliseconds */
    val totalGenerationTime: Long = 0,
    /** Time to first token in milliseconds */
    val timeToFirstToken: Long? = null,
    val averageTokensPerSecond: Double = 0.0,
)

@Serializable
@Immutable
data class MessageModelInfo(
    val modelId: String,
    val modelName: String,
    val framework: String? = null,
)

@Serializable
@Immutable
data class ToolCallInfo(
    val toolName: String,
    /** JSON string of arguments */
    val arguments: String,
    /** JSON string of result */
    val result: String? = null,
    val success: Boolean,
    val error: String? = null,
)
