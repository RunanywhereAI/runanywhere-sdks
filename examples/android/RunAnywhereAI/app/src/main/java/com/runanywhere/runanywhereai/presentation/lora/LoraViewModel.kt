package com.runanywhere.runanywhereai.presentation.lora

import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.LoRAAdapterConfig
import ai.runanywhere.proto.v1.LoRAAdapterInfo
import ai.runanywhere.proto.v1.LoRAApplyRequest
import ai.runanywhere.proto.v1.LoRARemoveRequest
import ai.runanywhere.proto.v1.LoRAState
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraAdapterCatalogListRequest
import ai.runanywhere.proto.v1.LoraAdapterCatalogListResult
import ai.runanywhere.proto.v1.LoraAdapterCatalogQuery
import ai.runanywhere.proto.v1.LoraAdapterDownloadCompletedRequest
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.cancelDownload
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.lora
import com.runanywhere.sdk.public.extensions.loraArtifactModelId
import com.runanywhere.sdk.public.extensions.model
import com.runanywhere.sdk.public.extensions.registerLoraArtifact
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber

data class LoraUiState(
    val registeredAdapters: List<LoraAdapterCatalogEntry> = emptyList(),
    val loadedAdapters: List<LoRAAdapterInfo> = emptyList(),
    val compatibleAdapters: List<LoraAdapterCatalogEntry> = emptyList(),
    val downloadingAdapterId: String? = null,
    val downloadProgress: Float = 0f,
    val error: String? = null,
)

/**
 * ViewModel for LoRA adapter management.
 * Handles listing, downloading, loading, and removing LoRA adapters.
 */
class LoraViewModel(application: Application) : AndroidViewModel(application) {
    private val _uiState = MutableStateFlow(LoraUiState())
    val uiState: StateFlow<LoraUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    /** Refresh all registered and loaded adapters. */
    fun refresh() {
        viewModelScope.launch {
            try {
                val (registered, loaded) =
                    withContext(Dispatchers.IO) {
                        catalogEntries() to loadCurrentState()
                    }
                _uiState.update {
                    it.copy(
                        registeredAdapters = registered,
                        loadedAdapters = loaded,
                        error = null,
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "Failed to refresh LoRA state")
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    /** Refresh compatible adapters for a specific model. */
    fun refreshForModel(modelId: String) {
        viewModelScope.launch {
            try {
                val (compatible, loaded) =
                    withContext(Dispatchers.IO) {
                        compatibleCatalogEntries(modelId) to loadCurrentState()
                    }
                _uiState.update {
                    it.copy(
                        compatibleAdapters = compatible,
                        loadedAdapters = loaded,
                        error = null,
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "Failed to refresh for model $modelId")
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    /** Load a LoRA adapter from a local file path. */
    fun loadAdapter(
        path: String,
        scale: Float = 1.0f,
    ) {
        viewModelScope.launch {
            try {
                val config = LoRAAdapterConfig(adapter_path = path, scale = scale)
                val result =
                    withContext(Dispatchers.IO) {
                        RunAnywhere.lora.apply(LoRAApplyRequest(adapters = listOf(config)))
                    }
                if (!result.success) {
                    throw IllegalStateException(result.error_message ?: "LoRA apply failed")
                }
                val loaded = result.adapters
                _uiState.update { it.copy(loadedAdapters = loaded, error = null) }
                Timber.i("Loaded LoRA adapter: $path (scale=$scale)")
            } catch (e: Exception) {
                Timber.e(e, "Failed to load LoRA adapter")
                _uiState.update { it.copy(error = "Failed to load adapter: ${e.message}") }
            }
        }
    }

    /** Remove a specific loaded adapter by path. */
    fun unloadAdapter(path: String) {
        viewModelScope.launch {
            try {
                val state =
                    withContext(Dispatchers.IO) {
                        RunAnywhere.lora.remove(LoRARemoveRequest(adapter_paths = listOf(path)))
                    }
                state.throwIfError()
                val loaded = state.loaded_adapters
                _uiState.update { it.copy(loadedAdapters = loaded, error = null) }
                Timber.i("Unloaded LoRA adapter: $path")
            } catch (e: Exception) {
                Timber.e(e, "Failed to unload LoRA adapter")
                _uiState.update { it.copy(error = "Failed to unload adapter: ${e.message}") }
            }
        }
    }

    /** Clear all loaded adapters. */
    fun clearAll() {
        viewModelScope.launch {
            try {
                val state =
                    withContext(Dispatchers.IO) {
                        RunAnywhere.lora.remove(LoRARemoveRequest(clear_all = true))
                    }
                state.throwIfError()
                _uiState.update { it.copy(loadedAdapters = emptyList(), error = null) }
                Timber.i("Cleared all LoRA adapters")
            } catch (e: Exception) {
                Timber.e(e, "Failed to clear LoRA adapters")
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    /** Check if a LoRA adapter file is compatible with the current model. */
    fun checkCompatibility(
        loraPath: String,
        onResult: (LoraCompatibilityResult) -> Unit,
    ) {
        viewModelScope.launch {
            val result =
                withContext(Dispatchers.IO) {
                    RunAnywhere.lora.checkCompatibility(LoRAAdapterConfig(adapter_path = loraPath))
                }
            onResult(result)
        }
    }

    /** Get the local file path for a catalog entry, or null if not downloaded. */
    fun localPath(entry: LoraAdapterCatalogEntry): String? {
        return currentCatalogEntry(entry.id)?.localPathOrNull() ?: entry.localPathOrNull()
    }

    /** Check if a catalog entry is already downloaded (reads from cached state). */
    fun isDownloaded(entry: LoraAdapterCatalogEntry): Boolean {
        return currentCatalogEntry(entry.id)?.isDownloadedLocally() ?: entry.isDownloadedLocally()
    }

    /** Check if a specific adapter is currently loaded. */
    fun isLoaded(entry: LoraAdapterCatalogEntry): Boolean {
        val path = localPath(entry) ?: return false
        return _uiState.value.loadedAdapters.any { it.adapter_path == path }
    }

    /** Start a generated registry/download flow for a LoRA artifact. */
    fun downloadAdapter(entry: LoraAdapterCatalogEntry) {
        if (_uiState.value.downloadingAdapterId != null) return

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    downloadingAdapterId = entry.id,
                    downloadProgress = 0f,
                    error = null,
                )
            }

            try {
                withContext(Dispatchers.IO) {
                    val artifact = RunAnywhere.registerLoraArtifact(entry)
                    RunAnywhere.downloadModel(artifact.id).collect { progress ->
                        _uiState.update {
                            it.copy(downloadProgress = progress.progressFraction())
                        }

                        when (progress.state) {
                            DownloadState.DOWNLOAD_STATE_COMPLETED -> {
                                val localPath =
                                    progress.local_path.ifBlank {
                                        RunAnywhere.model(entry.loraArtifactModelId)
                                            ?.local_path
                                            .orEmpty()
                                    }
                                val completedEntry =
                                    if (localPath.isNotBlank()) {
                                        val completion =
                                            RunAnywhere.lora.markDownloadCompleted(
                                                LoraAdapterDownloadCompletedRequest(
                                                    adapter_id = entry.id,
                                                    local_path = localPath,
                                                    size_bytes =
                                                        progress.total_bytes
                                                            .takeIf { it > 0L }
                                                            ?: entry.size_bytes.takeIf { it > 0L },
                                                    checksum_sha256 = entry.checksum_sha256,
                                                    completed_at_unix_ms =
                                                        progress.updated_at_unix_ms
                                                            .takeIf { it > 0L }
                                                            ?: System.currentTimeMillis(),
                                                    imported = false,
                                                    status_message = "download completed",
                                                ),
                                            )
                                        if (!completion.success) {
                                            throw IllegalStateException(
                                                completion.error_message.ifBlank {
                                                    "LoRA download completion was not persisted"
                                                },
                                            )
                                        }
                                        completion.entry
                                            ?: entry.copy(
                                                local_path = localPath,
                                                is_downloaded = true,
                                                downloaded_at_unix_ms = System.currentTimeMillis(),
                                                status_message = "download completed",
                                            )
                                    } else {
                                        null
                                    }
                                _uiState.update { state ->
                                    state.copy(
                                        registeredAdapters =
                                            completedEntry
                                                ?.let { state.registeredAdapters.replaceEntry(it) }
                                                ?: state.registeredAdapters,
                                        compatibleAdapters =
                                            completedEntry
                                                ?.let { state.compatibleAdapters.replaceEntry(it) }
                                                ?: state.compatibleAdapters,
                                        downloadingAdapterId = null,
                                        downloadProgress = 1f,
                                        error =
                                            if (completedEntry == null) {
                                                "LoRA download completed, but native download did not publish a local path yet."
                                            } else {
                                                null
                                            },
                                    )
                                }
                                Timber.i("Downloaded LoRA adapter through generated download flow: ${entry.id}")
                            }
                            DownloadState.DOWNLOAD_STATE_FAILED -> {
                                throw IllegalStateException(progress.error_message.ifBlank { "Download failed" })
                            }
                            DownloadState.DOWNLOAD_STATE_CANCELLED -> {
                                _uiState.update {
                                    it.copy(
                                        downloadingAdapterId = null,
                                        downloadProgress = 0f,
                                        error = null,
                                    )
                                }
                            }
                            else -> Unit
                        }
                    }
                }
            } catch (e: Exception) {
                Timber.e(e, "Failed to download LoRA adapter")
                _uiState.update {
                    it.copy(
                        downloadingAdapterId = null,
                        downloadProgress = 0f,
                        error = "Failed to download ${entry.name}: ${e.message}",
                    )
                }
            }
        }
    }

    /** Cancel an in-progress download. */
    fun cancelDownload() {
        val adapterId = _uiState.value.downloadingAdapterId
        val entry =
            adapterId?.let { id ->
                (_uiState.value.registeredAdapters + _uiState.value.compatibleAdapters)
                    .firstOrNull { it.id == id }
            }

        viewModelScope.launch {
            try {
                if (entry != null) {
                    withContext(Dispatchers.IO) {
                        RunAnywhere.cancelDownload(entry.loraArtifactModelId)
                    }
                }
            } catch (e: Exception) {
                Timber.w(e, "Failed to cancel LoRA download")
                _uiState.update { it.copy(error = "Failed to cancel download: ${e.message}") }
            } finally {
                _uiState.update {
                    it.copy(
                        downloadingAdapterId = null,
                        downloadProgress = 0f,
                    )
                }
            }
        }
    }

    /** Delete a downloaded adapter file. Always attempts unload first (ignores if not loaded). */
    fun deleteAdapter(entry: LoraAdapterCatalogEntry) {
        viewModelScope.launch {
            try {
                val loadedPath = localPath(entry)
                withContext(Dispatchers.IO) {
                    if (!loadedPath.isNullOrBlank()) {
                        RunAnywhere.lora
                            .remove(LoRARemoveRequest(adapter_paths = listOf(loadedPath)))
                            .throwIfError()
                    }
                    RunAnywhere.deleteModel(entry.loraArtifactModelId)
                }
                _uiState.update {
                    val clearedEntry =
                        entry.copy(
                            local_path = null,
                            is_downloaded = false,
                            downloaded_at_unix_ms = null,
                            status_message = "deleted",
                        )
                    it.copy(
                        registeredAdapters = it.registeredAdapters.replaceEntry(clearedEntry),
                        compatibleAdapters = it.compatibleAdapters.replaceEntry(clearedEntry),
                        loadedAdapters =
                            it.loadedAdapters.filterNot { adapter ->
                                adapter.adapter_path == loadedPath
                            },
                        error = null,
                    )
                }
                Timber.i("Deleted LoRA adapter through generated storage flow: ${entry.id}")
            } catch (e: Exception) {
                Timber.e(e, "Failed to delete LoRA adapter")
                _uiState.update {
                    it.copy(error = "Failed to delete ${entry.name}: ${e.message}")
                }
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    private suspend fun catalogEntries(): List<LoraAdapterCatalogEntry> {
        val result =
            RunAnywhere.lora.listCatalog(
                LoraAdapterCatalogListRequest(include_counts = true),
            )
        result.throwIfError("LoRA catalog list failed")
        return result.entries
    }

    private suspend fun compatibleCatalogEntries(modelId: String): List<LoraAdapterCatalogEntry> {
        val result =
            RunAnywhere.lora.queryCatalog(
                LoraAdapterCatalogQuery(
                    model_id = modelId,
                    downloaded_only = false,
                ),
            )
        result.throwIfError("LoRA catalog query failed")
        return result.entries
    }

    private suspend fun loadCurrentState(): List<LoRAAdapterInfo> {
        return try {
            val state = RunAnywhere.lora.list(LoRAState())
            if (state.error_message.isNullOrBlank()) state.loaded_adapters else emptyList()
        } catch (e: Exception) {
            Timber.w(e, "LoRA state unavailable")
            emptyList()
        }
    }

    private fun currentCatalogEntry(adapterId: String): LoraAdapterCatalogEntry? =
        (_uiState.value.registeredAdapters + _uiState.value.compatibleAdapters)
            .firstOrNull { it.id == adapterId }

    private fun List<LoraAdapterCatalogEntry>.replaceEntry(entry: LoraAdapterCatalogEntry): List<LoraAdapterCatalogEntry> =
        if (any { it.id == entry.id }) {
            map { if (it.id == entry.id) entry else it }
        } else {
            this
        }

    private fun LoraAdapterCatalogEntry.localPathOrNull(): String? = local_path?.takeIf { it.isNotBlank() }

    private fun LoraAdapterCatalogEntry.isDownloadedLocally(): Boolean = localPathOrNull() != null && is_downloaded != false

    private fun LoraAdapterCatalogListResult.throwIfError(prefix: String) {
        if (!success) {
            throw IllegalStateException(error_message.ifBlank { prefix })
        }
    }

    private fun LoRAState.throwIfError() {
        if (!error_message.isNullOrBlank()) {
            throw IllegalStateException(error_message)
        }
    }

    private fun DownloadProgress.progressFraction(): Float {
        val progress = if (overall_progress > 0f) overall_progress else stage_progress
        return progress.coerceIn(0f, 1f)
    }
}
