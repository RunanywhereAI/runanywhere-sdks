package com.runanywhere.runanywhereai.data.cloud

import kotlinx.serialization.Serializable

// Wire-format presets for a cloud STT vendor. The preset carries the vendor's
// default endpoint + model; the actual request/response shape lives in
// CloudProviderHandlers. Adding a vendor = a new entry here + a branch there.
@Serializable
enum class CloudPreset(
    val label: String,
    val defaultBaseUrl: String,
    val defaultModel: String,
) {
    SARVAM("Sarvam", "https://api.sarvam.ai", "saaras:v3"),
    OPENAI("OpenAI Whisper", "https://api.openai.com", "whisper-1"),
    OPENROUTER("OpenRouter", "https://openrouter.ai/api/v1", "openai/whisper-1"),
}

// A developer-registered cloud STT provider. Persisted by CloudProviderRepository
// and registered with the SDK via Cloud.registerProvider/Cloud.register.
@Serializable
data class CloudProviderConfig(
    val id: String,
    val label: String,
    val preset: CloudPreset,
    val model: String,
    val apiKey: String,
    val baseUrl: String,
)
