package com.runanywhere.runanywhereai.ui.screens.lora

import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.download.DownloadProgressInfo
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.lora
import com.runanywhere.sdk.public.api.models
import com.runanywhere.sdk.public.extensions.loraCatalog
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

data class LoraUiState(
    val adapters: List<LoraAdapterCatalogEntry> = emptyList(),
    val activeId: String? = null,
    val busyId: String? = null,
    val progress: DownloadProgressInfo? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
)

class LoraViewModel : ViewModel() {

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
            state = state.copy(busyId = entry.id, progress = DownloadProgressInfo(), error = null)
            try {
                val path =
                    adapterLocalPath(entry) ?: run {
                        // LoraAdapterCatalogEntry no longer carries url/filename/size
                        // (idl/lora_options.proto: "everything generic about the
                        // artifact ... lives on the ModelInfo record for this
                        // adapter"), so lora.download() now takes the companion
                        // ModelInfo artifact directly -- looked up under the
                        // `lora-adapter:{id}` convention ModelBootstrap/seedLora
                        // registers it under.
                        val artifact = RunAnywhere.models.get(loraArtifactModelId(entry.id))
                            ?: throw SDKException.modelNotFound(entry.id)
                        RunAnywhere.loraCatalog.download(entry, artifact) { progress ->
                            state = state.copy(progress = DownloadProgressInfo.from(progress))
                        }
                    }

                if (path.isNotBlank()) {
                    downloadedPaths[entry.id] = path
                }
                state = state.copy(busyId = null, progress = null)
                reload()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("lora download failed: ${entry.id}", e)
                state = state.copy(busyId = null, progress = null, error = e.message ?: "Download failed")
            }
        }
    }

    fun apply(entry: LoraAdapterCatalogEntry, scale: Float? = null) {
        val path = adapterLocalPath(entry)
        if (path.isNullOrBlank()) {
            state = state.copy(error = "Adapter not downloaded yet")
            return
        }
        viewModelScope.launch {
            state = state.copy(busyId = entry.id, error = null)
            try {
                // Pass unset through so commons resolve_effective_lora_scale owns
                // catalog/1.0 fallback (including honoring explicit catalog 0.0).
                RunAnywhere.lora.apply(entry.id, scale)
                GlobalState.lora.set(entry.id)
                state = state.copy(busyId = null, activeId = entry.id)
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
                RunAnywhere.lora.remove()
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

    // LoraAdapterCatalogEntry.is_downloaded was deleted outright; a non-empty
    // local_path is the proto's sole documented "is this downloaded" signal.
    fun isDownloaded(entry: LoraAdapterCatalogEntry): Boolean =
        adapterLocalPath(entry) != null

    private fun adapterLocalPath(entry: LoraAdapterCatalogEntry): String? =
        downloadedPaths[entry.id]
            ?: entry.local_path?.takeIf { it.isNotBlank() }

    /**
     * Stable model-registry id for a LoRA adapter's downloadable artifact.
     * `LoraAdapterCatalogEntry` no longer carries url/filename/size
     * (idl/lora_options.proto), so its bytes are described by a companion
     * [com.runanywhere.sdk.public.types.RAModelInfo] artifact keyed by this
     * id -- the same `lora-adapter:{id}` convention commons and the other
     * SDKs' reference LoRA extensions use.
     */
    private fun loraArtifactModelId(adapterId: String): String = "lora-adapter:$adapterId"

    private suspend fun reload() {
        val modelId = GlobalState.model.loaded?.id
        if (modelId == null) {
            state = state.copy(adapters = emptyList(), activeId = null, isLoading = false)
            return
        }
        try {
            val adapters = RunAnywhere.loraCatalog.adaptersForModel(modelId)
            adapters.forEach { entry ->
                entry.local_path?.takeIf { it.isNotBlank() }?.let { path ->
                    downloadedPaths[entry.id] = path
                }
            }
            val active = RunAnywhere.lora.list().applied.firstOrNull()?.id?.takeIf { it.isNotEmpty() }
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
