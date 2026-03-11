package com.runanywhere.runanywhereai.viewmodels

import android.app.Application
import android.util.Log
import androidx.compose.runtime.Immutable
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.models.collectDeviceInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LoraAdapterCatalogEntry
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
import com.runanywhere.sdk.public.extensions.Models.DownloadState
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.availableModels
import com.runanywhere.sdk.public.extensions.cancelDownload
import com.runanywhere.sdk.public.extensions.currentLLMModel
import com.runanywhere.sdk.public.extensions.clearLoraAdapters
import com.runanywhere.sdk.public.extensions.currentLLMModelId
import com.runanywhere.sdk.public.extensions.downloadLoraAdapter
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.isLLMModelLoaded
import com.runanywhere.sdk.public.extensions.getLoadedLoraAdapters
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.loadLoraAdapter
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import com.runanywhere.sdk.public.extensions.loadVLMModel
import com.runanywhere.sdk.public.extensions.loraAdapterLocalPath
import com.runanywhere.sdk.public.extensions.loraAdaptersForModel
import com.runanywhere.sdk.public.extensions.removeLoraAdapter
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@Immutable
data class DownloadInfo(
    val progress: Float = 0f,
    val bytesDownloaded: Long = 0L,
    val totalBytes: Long? = null,
    val speedBytesPerSec: Long = 0L,
) {
    val formattedProgress: String
        get() {
            val downloaded = formatBytes(bytesDownloaded)
            val total = totalBytes?.let { formatBytes(it) } ?: "?"
            val speed = formatBytes(speedBytesPerSec) + "/s"
            return "$downloaded / $total · $speed"
        }
}

@Immutable
data class ModelSelectionUiState(
    val context: ModelSelectionContext = ModelSelectionContext.LLM,
    val deviceInfo: DeviceInfo? = null,
    val models: ImmutableList<ModelInfo> = persistentListOf(),
    val selectedModelId: String? = null,
    val isLoadingModel: Boolean = false,
    val loadingModelId: String? = null,
    val downloadingModelId: String? = null,
    val modelDownloadInfo: DownloadInfo = DownloadInfo(),
    // LoRA
    val loraAdapters: ImmutableList<LoraAdapterCatalogEntry> = persistentListOf(),
    val loadedLoraAdapters: ImmutableList<LoRAAdapterInfo> = persistentListOf(),
    val downloadedAdapterPaths: Map<String, String> = emptyMap(),
    val downloadingAdapterId: String? = null,
    val loraDownloadInfo: DownloadInfo = DownloadInfo(),
    val error: String? = null,
) {
    val selectedModelSupportsLora: Boolean
        get() = models.find { it.id == selectedModelId }?.supportsLora == true

    val hasActiveLoraAdapters: Boolean
        get() = loadedLoraAdapters.isNotEmpty()
}

private fun formatBytes(bytes: Long): String = when {
    bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
    bytes >= 1_000_000 -> "%.1f MB".format(bytes / 1_000_000.0)
    bytes >= 1_000 -> "%.0f KB".format(bytes / 1_000.0)
    else -> "$bytes B"
}

class ModelSelectionViewModel(application: Application) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(ModelSelectionUiState())
    val uiState: StateFlow<ModelSelectionUiState> = _uiState.asStateFlow()

    private var modelDownloadJob: Job? = null
    private var loraDownloadJob: Job? = null

    // Speed tracking
    private var lastModelBytes: Long = 0L
    private var lastModelTimestamp: Long = 0L
    private var lastLoraBytes: Long = 0L
    private var lastLoraTimestamp: Long = 0L

    init {
        loadDeviceInfo()
        loadModels()
        subscribeToModelEvents()
    }

    private fun subscribeToModelEvents() {
        viewModelScope.launch {
            EventBus.events
                .filterIsInstance<ModelEvent>()
                .collect { event ->
                    when (event.eventType) {
                        ModelEvent.ModelEventType.DOWNLOAD_COMPLETED,
                        ModelEvent.ModelEventType.DELETED -> loadModels()
                        else -> { /* no-op */ }
                    }
                }
        }
    }

    private fun loadDeviceInfo() {
        viewModelScope.launch {
            try {
                val info = withContext(Dispatchers.IO) { collectDeviceInfo() }
                _uiState.update { it.copy(deviceInfo = info) }
            } catch (e: Exception) {
                Log.d(TAG, "Failed to collect device info", e)
            }
        }
    }

    fun loadModels(context: ModelSelectionContext = _uiState.value.context) {
        viewModelScope.launch {
            try {
                val (allModels, currentModelId, isLoaded) = withContext(Dispatchers.IO) {
                    val models = RunAnywhere.availableModels()
                    val currentId = RunAnywhere.currentLLMModelId
                    val loaded = RunAnywhere.isLLMModelLoaded()
                    Triple(models, currentId, loaded)
                }

                // Workaround: SDK cache may retain stale localPath after deletion.
                // Verify files actually exist on disk before treating as downloaded.
                val verified = allModels.map { model ->
                    val path = model.localPath
                    if (path != null && !path.startsWith("builtin://") && !File(path).exists()) {
                        model.copy(localPath = null)
                    } else {
                        model
                    }
                }

                // Filter by context, sort downloaded first
                val filtered = verified
                    .filter { context.isCategoryRelevant(it.category) }
                    .sortedWith(compareByDescending<ModelInfo> { it.isDownloaded }.thenBy { it.name })
                    .toImmutableList()

                // Only show selected if model is actually loaded
                val activeModelId = if (isLoaded) currentModelId else null

                _uiState.update {
                    it.copy(
                        context = context,
                        models = filtered,
                        selectedModelId = activeModelId,
                        error = null,
                    )
                }

                // Load LoRA state for current model
                if (currentModelId != null && context == ModelSelectionContext.LLM) {
                    refreshLoraForModel(currentModelId)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load models", e)
                _uiState.update { it.copy(error = e.message) }
            }
        }
    }

    fun selectModel(modelId: String, onSuccess: ((name: String, supportsLora: Boolean) -> Unit)? = null) {
        if (_uiState.value.isLoadingModel) return
        val context = _uiState.value.context

        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingModel = true, loadingModelId = modelId, error = null) }
            try {
                withContext(Dispatchers.IO) {
                    when (context) {
                        ModelSelectionContext.LLM, ModelSelectionContext.RAG_LLM -> {
                            try { RunAnywhere.clearLoraAdapters() } catch (_: Exception) { }
                            RunAnywhere.loadLLMModel(modelId)
                        }
                        ModelSelectionContext.STT -> RunAnywhere.loadSTTModel(modelId)
                        ModelSelectionContext.TTS, ModelSelectionContext.VOICE -> RunAnywhere.loadTTSVoice(modelId)
                        ModelSelectionContext.VLM -> RunAnywhere.loadVLMModel(modelId)
                        ModelSelectionContext.RAG_EMBEDDING -> {
                            // Embedding models are loaded via RAG pipeline, not directly.
                            // Just mark as selected — no SDK load call needed.
                        }
                    }
                }

                // Get model name for display
                val name: String
                val supportsLora: Boolean
                if (context == ModelSelectionContext.LLM) {
                    val modelInfo = withContext(Dispatchers.IO) { RunAnywhere.currentLLMModel() }
                    name = modelInfo?.name ?: modelId
                    supportsLora = modelInfo?.supportsLora == true
                } else {
                    // For non-LLM models, derive name from the model list
                    name = _uiState.value.models.find { it.id == modelId }?.name ?: modelId
                    supportsLora = false
                }

                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        loadingModelId = null,
                        selectedModelId = modelId,
                        loadedLoraAdapters = if (context == ModelSelectionContext.LLM) persistentListOf() else it.loadedLoraAdapters,
                    )
                }
                onSuccess?.invoke(name, supportsLora)
                if (context == ModelSelectionContext.LLM) {
                    refreshLoraForModel(modelId)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load model: $modelId", e)
                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        loadingModelId = null,
                        error = "Failed to load model: ${e.message}",
                    )
                }
            }
        }
    }

    fun downloadModel(modelId: String) {
        if (_uiState.value.downloadingModelId != null) return

        lastModelBytes = 0L
        lastModelTimestamp = System.currentTimeMillis()
        _uiState.update { it.copy(downloadingModelId = modelId, modelDownloadInfo = DownloadInfo(), error = null) }

        modelDownloadJob = viewModelScope.launch {
            try {
                RunAnywhere.downloadModel(modelId).collect { progress ->
                    val now = System.currentTimeMillis()
                    val speed = calculateSpeed(
                        prevBytes = lastModelBytes, newBytes = progress.bytesDownloaded,
                        prevTime = lastModelTimestamp, newTime = now,
                    )
                    if (speed != null) {
                        lastModelBytes = progress.bytesDownloaded
                        lastModelTimestamp = now
                    }

                    _uiState.update {
                        it.copy(
                            modelDownloadInfo = it.modelDownloadInfo.copy(
                                progress = progress.progress,
                                bytesDownloaded = progress.bytesDownloaded,
                                totalBytes = progress.totalBytes,
                                speedBytesPerSec = speed ?: it.modelDownloadInfo.speedBytesPerSec,
                            ),
                        )
                    }

                    if (progress.state == DownloadState.COMPLETED) {
                        Log.i(TAG, "Model downloaded: $modelId")
                        _uiState.update { it.copy(downloadingModelId = null, modelDownloadInfo = DownloadInfo()) }
                        loadModels()
                    }
                }
                if (_uiState.value.downloadingModelId != null) {
                    _uiState.update { it.copy(downloadingModelId = null, modelDownloadInfo = DownloadInfo()) }
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Download failed: $modelId", e)
                _uiState.update {
                    it.copy(downloadingModelId = null, modelDownloadInfo = DownloadInfo(), error = "Download failed: ${e.message}")
                }
            }
        }
    }

    fun cancelModelDownload() {
        val modelId = _uiState.value.downloadingModelId ?: return
        modelDownloadJob?.cancel()
        modelDownloadJob = null
        viewModelScope.launch {
            try { withContext(Dispatchers.IO) { RunAnywhere.cancelDownload(modelId) } } catch (_: Exception) {}
        }
        _uiState.update { it.copy(downloadingModelId = null, modelDownloadInfo = DownloadInfo()) }
    }

    // LoRA

    fun refreshLoraForModel(modelId: String) {
        viewModelScope.launch {
            try {
                val (compatible, loaded, downloaded) = withContext(Dispatchers.IO) {
                    val compat = RunAnywhere.loraAdaptersForModel(modelId)
                    val loadedAdapters = RunAnywhere.getLoadedLoraAdapters()
                    val paths = compat.mapNotNull { entry ->
                        val path = RunAnywhere.loraAdapterLocalPath(entry.id)
                        if (path != null) entry.id to path else null
                    }.toMap()
                    Triple(compat, loadedAdapters, paths)
                }
                _uiState.update {
                    it.copy(
                        loraAdapters = compatible.toImmutableList(),
                        loadedLoraAdapters = loaded.toImmutableList(),
                        downloadedAdapterPaths = it.downloadedAdapterPaths + downloaded,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to refresh LoRA for model: $modelId", e)
            }
        }
    }

    fun loadLoraAdapter(adapterId: String, scale: Float = 1.0f) {
        val path = _uiState.value.downloadedAdapterPaths[adapterId] ?: return
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path = path, scale = scale))
                }
                val loaded = withContext(Dispatchers.IO) { RunAnywhere.getLoadedLoraAdapters() }
                _uiState.update { it.copy(loadedLoraAdapters = loaded.toImmutableList(), error = null) }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load LoRA adapter", e)
                _uiState.update { it.copy(error = "Failed to apply adapter: ${e.message}") }
            }
        }
    }

    fun unloadLoraAdapter(adapterId: String) {
        val path = _uiState.value.downloadedAdapterPaths[adapterId] ?: return
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { RunAnywhere.removeLoraAdapter(path) }
                val loaded = withContext(Dispatchers.IO) { RunAnywhere.getLoadedLoraAdapters() }
                _uiState.update { it.copy(loadedLoraAdapters = loaded.toImmutableList(), error = null) }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to unload LoRA adapter", e)
                _uiState.update { it.copy(error = "Failed to remove adapter: ${e.message}") }
            }
        }
    }

    fun downloadLoraAdapter(entry: LoraAdapterCatalogEntry) {
        if (_uiState.value.downloadingAdapterId != null) return

        lastLoraBytes = 0L
        lastLoraTimestamp = System.currentTimeMillis()
        _uiState.update { it.copy(downloadingAdapterId = entry.id, loraDownloadInfo = DownloadInfo(), error = null) }

        loraDownloadJob = viewModelScope.launch {
            try {
                RunAnywhere.downloadLoraAdapter(entry.id).collect { progress ->
                    val now = System.currentTimeMillis()
                    val speed = calculateSpeed(
                        prevBytes = lastLoraBytes, newBytes = progress.bytesDownloaded,
                        prevTime = lastLoraTimestamp, newTime = now,
                    )
                    if (speed != null) {
                        lastLoraBytes = progress.bytesDownloaded
                        lastLoraTimestamp = now
                    }

                    _uiState.update {
                        it.copy(
                            loraDownloadInfo = it.loraDownloadInfo.copy(
                                progress = progress.progress,
                                bytesDownloaded = progress.bytesDownloaded,
                                totalBytes = progress.totalBytes,
                                speedBytesPerSec = speed ?: it.loraDownloadInfo.speedBytesPerSec,
                            ),
                        )
                    }

                    if (progress.state == DownloadState.COMPLETED) {
                        val path = RunAnywhere.loraAdapterLocalPath(entry.id)
                        _uiState.update {
                            it.copy(
                                downloadingAdapterId = null,
                                loraDownloadInfo = DownloadInfo(),
                                downloadedAdapterPaths = if (path != null)
                                    it.downloadedAdapterPaths + (entry.id to path)
                                else it.downloadedAdapterPaths,
                            )
                        }
                    }
                }
                if (_uiState.value.downloadingAdapterId != null) {
                    _uiState.update { it.copy(downloadingAdapterId = null, loraDownloadInfo = DownloadInfo()) }
                }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e(TAG, "Failed to download LoRA adapter: ${entry.name}", e)
                _uiState.update {
                    it.copy(downloadingAdapterId = null, loraDownloadInfo = DownloadInfo(), error = "Download failed: ${e.message}")
                }
            }
        }
    }

    fun cancelLoraDownload() {
        loraDownloadJob?.cancel()
        loraDownloadJob = null
        _uiState.update { it.copy(downloadingAdapterId = null, loraDownloadInfo = DownloadInfo()) }
    }

    fun isLoraLoaded(adapterId: String): Boolean {
        val path = _uiState.value.downloadedAdapterPaths[adapterId] ?: return false
        return _uiState.value.loadedLoraAdapters.any { it.path == path }
    }

    fun isLoraDownloaded(adapterId: String): Boolean {
        return adapterId in _uiState.value.downloadedAdapterPaths
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    /** Returns speed in bytes/sec, or null if interval too short (avoids spiky readings). */
    private fun calculateSpeed(prevBytes: Long, newBytes: Long, prevTime: Long, newTime: Long): Long? {
        val dt = newTime - prevTime
        if (dt < 300) return null // only update every 300ms
        val db = newBytes - prevBytes
        return if (db > 0) (db * 1000L) / dt else 0L
    }

    companion object {
        private const val TAG = "ModelSelectionVM"
    }
}
