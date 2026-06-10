package com.runanywhere.runanywhereai.data.settings

data class AppSettings(
    val temperature: Float = 0.7f,
    val maxTokens: Int = 1024,
    val systemPrompt: String = "",
    val streaming: Boolean = true,
    val toolCallingEnabled: Boolean = false,
)
