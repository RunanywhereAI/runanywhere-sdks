package com.runanywhere.runanywhereai.ui.screens.settings

import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelListRequest
import ai.runanywhere.proto.v1.StorageInfoRequest
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.ModelBootstrap
import com.runanywhere.runanywhereai.data.settings.AppSettings
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.screens.models.LlmModelChangeInterlock
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.extensions.Models.isBuiltIn
import com.runanywhere.sdk.public.extensions.cleanTempFiles
import com.runanywhere.sdk.public.extensions.clearCache
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.getStorageInfo
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.matchesLifecycleCategory
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

data class StorageUiState(
    val freeBytes: Long = 0,
    val totalBytes: Long = 0,
    val modelsBytes: Long = 0,
    val downloaded: List<RAModelInfo> = emptyList(),
    val isLoading: Boolean = true,
    val hfTokenBusy: Boolean = false,
    val hfTokenMessage: String? = null,
    val hfTokenMessageIsError: Boolean = false,
    val busyId: String? = null,
    val message: String? = null,
)

class SettingsViewModel : ViewModel() {

    val settings: AppSettings get() = SettingsRepository.settings
    val sdkVersion: String get() = RunAnywhere.version

    var storage by mutableStateOf(StorageUiState())
        private set

    var hfTokenDraft by mutableStateOf(SettingsRepository.settings.hfToken)
        private set

    init {
        refreshStorage()
    }

    fun setTemperature(value: Float) = SettingsRepository.setTemperature(value)
    fun setMaxTokens(value: Int) = SettingsRepository.setMaxTokens(value)
    fun setSystemPrompt(value: String) = SettingsRepository.setSystemPrompt(value)
    fun setStreaming(value: Boolean) = SettingsRepository.setStreaming(value)
    fun setDisableThinking(value: Boolean) = SettingsRepository.setDisableThinking(value)

    fun editHfToken(value: String) {
        hfTokenDraft = value
        storage = storage.copy(hfTokenMessage = null, hfTokenMessageIsError = false)
    }

    fun commitHfToken() {
        if (storage.hfTokenBusy) return
        val candidate = hfTokenDraft.trim()
        viewModelScope.launch {
            val clearing = candidate.isBlank()
            storage = storage.copy(hfTokenBusy = true, hfTokenMessage = null, hfTokenMessageIsError = false)
            val persistenceFailure = SettingsRepository.setHfToken(candidate).exceptionOrNull()
            if (persistenceFailure != null) {
                RACLog.e("Hugging Face token secure-storage update failed", persistenceFailure)
                storage = storage.copy(
                    hfTokenBusy = false,
                    hfTokenMessage = if (clearing) {
                        "Could not securely clear Hugging Face token"
                    } else {
                        "Could not securely save Hugging Face token"
                    },
                    hfTokenMessageIsError = true,
                )
                return@launch
            }
            hfTokenDraft = candidate
            try {
                // Empty clears the token (public no-auth behavior); never logged.
                RunAnywhere.setHfToken(candidate)
                ModelBootstrap.refreshNpuCatalog()
                storage = storage.copy(
                    hfTokenBusy = false,
                    hfTokenMessage = if (clearing) {
                        "Hugging Face token cleared"
                    } else {
                        "Hugging Face token saved"
                    },
                    hfTokenMessageIsError = false,
                )
                refreshStorage()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("Hugging Face token was saved but could not be applied", e)
                storage = storage.copy(
                    hfTokenBusy = false,
                    hfTokenMessage = "Token saved securely. Reopen the app to apply it.",
                    hfTokenMessageIsError = true,
                )
            }
        }
    }

    fun clearHfToken() {
        hfTokenDraft = ""
        commitHfToken()
    }

    fun refreshStorage() {
        viewModelScope.launch {
            val info = runCatching {
                RunAnywhere.getStorageInfo(
                    StorageInfoRequest(include_device = true, include_app = true, include_models = true),
                ).info
            }.getOrNull()
            val models = runCatching {
                RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
                    .filter { it.isDownloadedOnDisk && !it.isBuiltIn }
            }.getOrDefault(emptyList())
            storage = storage.copy(
                freeBytes = info?.device?.free_bytes ?: 0,
                totalBytes = info?.device?.total_bytes ?: 0,
                modelsBytes = info?.total_models_bytes ?: 0,
                downloaded = models,
                isLoading = false,
            )
        }
    }

    fun deleteModel(model: RAModelInfo) {
        viewModelScope.launch {
            storage = storage.copy(busyId = model.id, message = null)
            try {
                // Deleting the actively-generating LLM tears down process-wide
                // native state. Let the chat's interlock revoke and fully cancel
                // any in-flight request first, mirroring
                // ModelSelectionViewModel.delete, so we don't race native
                // teardown. Non-LLM models have no such interlock.
                if (model.matchesLifecycleCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)) {
                    LlmModelChangeInterlock.awaitReadyForModelChange()
                }
                RunAnywhere.deleteModel(model.id)
                RuntimeModelSelection.clearModelEverywhere(model.id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("delete model failed: ${model.id}", e)
                storage = storage.copy(message = e.message ?: "Delete failed")
            }
            storage = storage.copy(busyId = null)
            refreshStorage()
        }
    }

    fun clearCache() = runStorageAction("Cache cleared") { RunAnywhere.clearCache() }

    fun cleanTempFiles() = runStorageAction("Temporary files cleaned") { RunAnywhere.cleanTempFiles() }

    private fun runStorageAction(success: String, action: suspend () -> Unit) {
        viewModelScope.launch {
            storage = try {
                action()
                storage.copy(message = success)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("storage action failed", e)
                storage.copy(message = e.message ?: "Action failed")
            }
            refreshStorage()
        }
    }

    fun clearMessage() {
        storage = storage.copy(message = null, hfTokenMessage = null, hfTokenMessageIsError = false)
    }
}
