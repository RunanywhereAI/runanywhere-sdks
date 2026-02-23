package com.runanywhere.runanywhereai.presentation.lora

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LoraAdapterCatalogEntry
import com.runanywhere.sdk.public.extensions.LoraCompatibilityResult
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
import com.runanywhere.sdk.public.extensions.allRegisteredLoraAdapters
import com.runanywhere.sdk.public.extensions.checkLoraCompatibility
import com.runanywhere.sdk.public.extensions.clearLoraAdapters
import com.runanywhere.sdk.public.extensions.getLoadedLoraAdapters
import com.runanywhere.sdk.public.extensions.loadLoraAdapter
import com.runanywhere.sdk.public.extensions.loraAdaptersForModel
import com.runanywhere.sdk.public.extensions.removeLoraAdapter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.URL

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
    private var downloadJob: Job? = null

    private val loraDir: File by lazy {
        File(application.filesDir, "lora_adapters").also { it.mkdirs() }
    }

    init {
        refresh()
    }

    /** Refresh all registered and loaded adapters. */
    fun refresh() {
        viewModelScope.launch {
            try {
                val registered = RunAnywhere.allRegisteredLoraAdapters()
                val loaded = RunAnywhere.getLoadedLoraAdapters()
                _uiState.value = _uiState.value.copy(
                    registeredAdapters = registered,
                    loadedAdapters = loaded,
                    error = null,
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to refresh LoRA state", e)
                _uiState.value = _uiState.value.copy(error = e.message)
            }
        }
    }

    /** Refresh compatible adapters for a specific model. */
    fun refreshForModel(modelId: String) {
        viewModelScope.launch {
            try {
                val compatible = RunAnywhere.loraAdaptersForModel(modelId)
                val loaded = RunAnywhere.getLoadedLoraAdapters()
                _uiState.value = _uiState.value.copy(
                    compatibleAdapters = compatible,
                    loadedAdapters = loaded,
                    error = null,
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to refresh for model $modelId", e)
                _uiState.value = _uiState.value.copy(error = e.message)
            }
        }
    }

    /** Load a LoRA adapter from a local file path. */
    fun loadAdapter(path: String, scale: Float = 1.0f) {
        viewModelScope.launch {
            try {
                val config = LoRAAdapterConfig(path = path, scale = scale)
                RunAnywhere.loadLoraAdapter(config)
                val loaded = RunAnywhere.getLoadedLoraAdapters()
                _uiState.value = _uiState.value.copy(loadedAdapters = loaded, error = null)
                Log.i(TAG, "Loaded LoRA adapter: $path (scale=$scale)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load LoRA adapter", e)
                _uiState.value = _uiState.value.copy(error = "Failed to load adapter: ${e.message}")
            }
        }
    }

    /** Remove a specific loaded adapter by path. */
    fun unloadAdapter(path: String) {
        viewModelScope.launch {
            try {
                RunAnywhere.removeLoraAdapter(path)
                val loaded = RunAnywhere.getLoadedLoraAdapters()
                _uiState.value = _uiState.value.copy(loadedAdapters = loaded, error = null)
                Log.i(TAG, "Unloaded LoRA adapter: $path")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to unload LoRA adapter", e)
                _uiState.value = _uiState.value.copy(error = "Failed to unload adapter: ${e.message}")
            }
        }
    }

    /** Clear all loaded adapters. */
    fun clearAll() {
        viewModelScope.launch {
            try {
                RunAnywhere.clearLoraAdapters()
                _uiState.value = _uiState.value.copy(loadedAdapters = emptyList(), error = null)
                Log.i(TAG, "Cleared all LoRA adapters")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear LoRA adapters", e)
                _uiState.value = _uiState.value.copy(error = e.message)
            }
        }
    }

    /** Check if a LoRA adapter file is compatible with the current model. */
    fun checkCompatibility(loraPath: String, onResult: (LoraCompatibilityResult) -> Unit) {
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                RunAnywhere.checkLoraCompatibility(loraPath)
            }
            onResult(result)
        }
    }

    /** Get the local file path for a catalog entry, or null if not downloaded. */
    fun localPath(entry: LoraAdapterCatalogEntry): String? {
        val file = File(loraDir, entry.filename)
        return if (file.exists()) file.absolutePath else null
    }

    /** Check if a catalog entry is already downloaded. */
    fun isDownloaded(entry: LoraAdapterCatalogEntry): Boolean {
        return File(loraDir, entry.filename).exists()
    }

    /** Check if a specific adapter is currently loaded. */
    fun isLoaded(entry: LoraAdapterCatalogEntry): Boolean {
        val path = localPath(entry) ?: return false
        return _uiState.value.loadedAdapters.any { it.path == path }
    }

    /** Download a LoRA adapter GGUF file. */
    fun downloadAdapter(entry: LoraAdapterCatalogEntry) {
        if (_uiState.value.downloadingAdapterId != null) return

        _uiState.value = _uiState.value.copy(
            downloadingAdapterId = entry.id,
            downloadProgress = 0f,
            error = null,
        )

        downloadJob = viewModelScope.launch {
            try {
                val destFile = File(loraDir, entry.filename)
                val tmpFile = File(loraDir, "${entry.filename}.tmp")
                withContext(Dispatchers.IO) {
                    val connection = URL(entry.downloadUrl).openConnection().apply {
                        connectTimeout = 30_000
                        readTimeout = 60_000
                    }
                    connection.connect()
                    val totalSize = connection.contentLengthLong.takeIf { it > 0 } ?: entry.fileSize
                    var downloaded = 0L

                    connection.getInputStream().buffered().use { input ->
                        tmpFile.outputStream().buffered().use { output ->
                            val buffer = ByteArray(8192)
                            var bytesRead: Int
                            while (input.read(buffer).also { bytesRead = it } != -1) {
                                output.write(buffer, 0, bytesRead)
                                downloaded += bytesRead
                                if (totalSize > 0) {
                                    val progress = (downloaded.toFloat() / totalSize).coerceIn(0f, 1f)
                                    _uiState.value = _uiState.value.copy(downloadProgress = progress)
                                }
                            }
                        }
                    }
                    tmpFile.renameTo(destFile)
                }

                Log.i(TAG, "Downloaded LoRA adapter: ${entry.name} -> ${destFile.absolutePath}")
                _uiState.value = _uiState.value.copy(
                    downloadingAdapterId = null,
                    downloadProgress = 0f,
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to download LoRA adapter: ${entry.name}", e)
                _uiState.value = _uiState.value.copy(
                    downloadingAdapterId = null,
                    downloadProgress = 0f,
                    error = "Download failed: ${e.message}",
                )
            }
        }
    }

    /** Cancel an in-progress download. */
    fun cancelDownload() {
        downloadJob?.cancel()
        downloadJob = null
        _uiState.value = _uiState.value.copy(
            downloadingAdapterId = null,
            downloadProgress = 0f,
        )
    }

    /** Delete a downloaded adapter file. Unloads the adapter first if loaded. */
    fun deleteAdapter(entry: LoraAdapterCatalogEntry) {
        viewModelScope.launch {
            try {
                val file = File(loraDir, entry.filename)
                // Unload first if currently loaded
                if (isLoaded(entry)) {
                    file.absolutePath.let { RunAnywhere.removeLoraAdapter(it) }
                    Log.i(TAG, "Unloaded LoRA adapter before delete: ${entry.filename}")
                }
                if (file.exists()) {
                    file.delete()
                    Log.i(TAG, "Deleted LoRA adapter file: ${entry.filename}")
                }
                val loaded = RunAnywhere.getLoadedLoraAdapters()
                _uiState.value = _uiState.value.copy(loadedAdapters = loaded)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete adapter: ${entry.filename}", e)
                _uiState.value = _uiState.value.copy(error = "Delete failed: ${e.message}")
            }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }

    companion object {
        private const val TAG = "LoraViewModel"
    }
}
