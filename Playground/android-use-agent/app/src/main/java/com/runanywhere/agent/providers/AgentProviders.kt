package com.runanywhere.agent.providers

/**
 * Tracks which provider is actively handling reasoning.
 * Emitted as events so the UI can show clear indicators.
 */
enum class ProviderMode(val label: String) {
    LOCAL("On-Device"),
    LOCAL_NO_VISION("On-Device (text)"),
    CLOUD("Cloud"),
    CLOUD_FALLBACK("Cloud (fallback)")
}
