package com.runanywhere.runanywhereai.ui.screens.cloud

import androidx.lifecycle.ViewModel
import com.runanywhere.runanywhereai.data.cloud.CloudPreset
import com.runanywhere.runanywhereai.data.cloud.CloudProviderConfig
import com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository

class CloudProvidersViewModel : ViewModel() {

    val providers: List<CloudProviderConfig> get() = CloudProviderRepository.providers

    fun save(
        existingId: String?,
        label: String,
        preset: CloudPreset,
        model: String,
        apiKey: String,
        baseUrl: String,
    ) {
        CloudProviderRepository.upsert(
            CloudProviderConfig(
                id = existingId ?: newId(label, preset),
                label = label.trim().ifBlank { preset.label },
                preset = preset,
                model = model.trim().ifBlank { preset.defaultModel },
                apiKey = apiKey.trim(),
                baseUrl = baseUrl.trim(),
            ),
        )
    }

    fun delete(id: String) = CloudProviderRepository.remove(id)

    // Stable per-provider id, also used as the SDK provider name + registry id.
    // Never "sarvam"/"saaras" so a custom provider can't collide with the built-in.
    private fun newId(label: String, preset: CloudPreset): String {
        val slug = label.lowercase().filter { it.isLetterOrDigit() }
            .take(12).ifBlank { preset.name.lowercase() }
        return "cloud-$slug-${System.currentTimeMillis().toString(36)}"
    }
}
