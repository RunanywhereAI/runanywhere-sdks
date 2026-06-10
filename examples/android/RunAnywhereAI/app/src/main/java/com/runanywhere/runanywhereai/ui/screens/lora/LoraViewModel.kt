package com.runanywhere.runanywhereai.ui.screens.lora

import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.lora
import com.runanywhere.sdk.public.types.RALoRAAdapterConfig
import com.runanywhere.sdk.public.types.RALoRAApplyRequest
import com.runanywhere.sdk.public.types.RALoRARemoveRequest
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import java.io.File
import kotlin.coroutines.cancellation.CancellationException

data class LoraUiState(
    val adapters: List<LoraAdapterCatalogEntry> = emptyList(),
    val activeId: String? = null,
    val busyId: String? = null,
    val progressPercent: Int? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
)

class LoraViewModel(application: Application) : AndroidViewModel(application) {

    var state by mutableStateOf(LoraUiState())
        private set

    private val downloadedPaths = mutableMapOf<String, String>()

    val modelName: String? get() = GlobalState.model.loaded?.name

    fun refresh() {
        viewModelScope.launch { reload() }
    }

    fun download(entry: LoraAdapterCatalogEntry) {
        if (isDownloaded(entry)) return
        viewModelScope.launch {
            state = state.copy(busyId = entry.id, progressPercent = 0, error = null)
            try {
                val existing = findAdapterFile(entry)
                val path = if (existing != null) {
                    existing.absolutePath
                } else {
                    RunAnywhere.lora.download(entry) { progress ->
                        val pct = if (progress.total_bytes > 0) {
                            (progress.bytes_downloaded * 100 / progress.total_bytes).toInt()
                        } else {
                            (progress.stage_progress.coerceIn(0f, 1f) * 100).toInt()
                        }
                        state = state.copy(progressPercent = pct)
                    }
                }

                if (path.isNotBlank()) {
                    downloadedPaths[entry.id] = path
                }
                state = state.copy(busyId = null, progressPercent = null)
                reload()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("lora download failed: ${entry.id}", e)
                state = state.copy(busyId = null, progressPercent = null, error = e.message ?: "Download failed")
            }
        }
    }

    fun apply(entry: LoraAdapterCatalogEntry) {
        val path = downloadedPaths[entry.id] ?: findAdapterFile(entry)?.absolutePath
        if (path.isNullOrBlank()) {
            state = state.copy(error = "Adapter not downloaded yet")
            return
        }
        viewModelScope.launch {
            state = state.copy(busyId = entry.id, error = null)
            try {
                val result = RunAnywhere.lora.apply(
                    RALoRAApplyRequest(
                        adapters = listOf(
                            RALoRAAdapterConfig(
                                adapter_path = path,
                                scale = entry.default_scale.takeIf { it > 0f } ?: 1f,
                                adapter_id = entry.id,
                            ),
                        ),
                        replace_existing = true,
                    ),
                )
                if (result.success) {
                    GlobalState.lora.set(entry.id)
                    state = state.copy(busyId = null, activeId = entry.id)
                } else {
                    state = state.copy(busyId = null, error = result.error_message?.ifBlank { null } ?: "Apply failed")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("lora apply failed: ${entry.id}", e)
                state = state.copy(busyId = null, error = e.message ?: "Apply failed")
            }
        }
    }

    fun clear() {
        viewModelScope.launch {
            try {
                RunAnywhere.lora.remove(RALoRARemoveRequest(clear_all = true))
                GlobalState.lora.set(null)
                state = state.copy(activeId = null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("lora clear failed", e)
                state = state.copy(error = e.message ?: "Failed to remove adapter")
            }
        }
    }

    fun clearError() {
        state = state.copy(error = null)
    }

    fun isDownloaded(entry: LoraAdapterCatalogEntry): Boolean =
        downloadedPaths.containsKey(entry.id) || findAdapterFile(entry) != null

    private fun adapterFilename(entry: LoraAdapterCatalogEntry): String =
        entry.filename.ifBlank { entry.url.substringAfterLast('/').substringBefore('?') }

    private fun findAdapterFile(entry: LoraAdapterCatalogEntry): File? {
        val name = adapterFilename(entry).ifBlank { return null }
        return getApplication<Application>().filesDir
            .walkTopDown()
            .firstOrNull { it.isFile && it.name == name && it.length() > 0 }
    }

    private suspend fun reload() {
        val modelId = GlobalState.model.loaded?.id
        if (modelId == null) {
            state = state.copy(adapters = emptyList(), activeId = null, isLoading = false)
            return
        }
        try {
            val adapters = RunAnywhere.lora.adaptersForModel(modelId)
            adapters.forEach { entry ->
                findAdapterFile(entry)?.let { downloadedPaths[entry.id] = it.absolutePath }
            }
            val active = RunAnywhere.lora.state().loaded_adapters
                .firstOrNull { it.applied }?.adapter_id?.takeIf { it.isNotEmpty() }
            GlobalState.lora.set(active)
            state = state.copy(adapters = adapters, activeId = active, isLoading = false, error = null)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("lora list failed", e)
            state = state.copy(isLoading = false, error = e.message ?: "Failed to load adapters")
        }
    }
}
