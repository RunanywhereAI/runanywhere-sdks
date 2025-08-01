package com.runanywhere.runanywhereai.llm

/**
 * Result of a text generation operation
 */
data class GenerationResult(
    val text: String,
    val tokensGenerated: Int,
    val timeMs: Long,
    val tokensPerSecond: Float
)
