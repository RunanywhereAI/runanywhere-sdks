package com.runanywhere.runanywhereai.ui.screens.cloud

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.runanywhere.runanywhereai.data.cloud.CloudPreset
import com.runanywhere.runanywhereai.data.cloud.CloudProviderConfig
import com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository

class CloudProvidersViewModel : ViewModel() {

    val providers: List<CloudProviderConfig> get() = CloudProviderRepository.providers

    var errorMessage: String? by mutableStateOf(null)
        private set

    fun save(
        existingId: String?,
        label: String,
        preset: CloudPreset,
        model: String,
        apiKey: String,
        baseUrl: String,
    ): Boolean {
        val result = CloudProviderRepository.upsert(
            CloudProviderConfig(
                id = existingId ?: newId(label, preset),
                label = label.trim().ifBlank { preset.label },
                preset = preset,
                model = model.trim().ifBlank { preset.defaultModel },
                apiKey = apiKey.trim(),
                baseUrl = baseUrl.trim(),
            ),
        )
        return result.fold(
            onSuccess = {
                errorMessage = null
                true
            },
            onFailure = {
                errorMessage = it.message ?: "Could not securely save cloud provider"
                false
            },
        )
    }

    fun delete(id: String) {
        CloudProviderRepository.remove(id).fold(
            onSuccess = { errorMessage = null },
            onFailure = { errorMessage = it.message ?: "Could not securely remove cloud provider" },
        )
    }

    fun clearError() {
        errorMessage = null
    }

    // Stable per-provider id, also used as the SDK provider name + registry id.
    private fun newId(label: String, preset: CloudPreset): String {
        val slug = label.lowercase().filter { it.isLetterOrDigit() }
            .take(12).ifBlank { preset.name.lowercase() }
        return "cloud-$slug-${System.currentTimeMillis().toString(36)}"
    }
}
