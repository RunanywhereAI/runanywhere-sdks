package com.runanywhere.run_anywhere_lora

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
import com.runanywhere.sdk.public.extensions.LoraDownloadState
import com.runanywhere.sdk.public.extensions.Models.DownloadState
import com.runanywhere.sdk.public.extensions.availableLoraAdapters
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.checkLoraCompatibility
import com.runanywhere.sdk.public.extensions.clearLoraAdapters
import com.runanywhere.sdk.public.extensions.downloadLoraAdapter
import com.runanywhere.sdk.public.extensions.downloadLoraFromCatalog
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.generateStreamWithMetrics
import com.runanywhere.sdk.public.extensions.getLoadedLoraAdapters
import com.runanywhere.sdk.public.extensions.isLLMModelLoaded
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.loadLoraAdapter
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.removeLoraAdapter
import com.runanywhere.sdk.public.extensions.unloadLLMModel
import com.runanywhere.sdk.temp.LoraAdapterCatalog
import com.runanywhere.sdk.temp.LoraAdapterEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

data class GenerationMetrics(
    val tokensPerSecond: Double,
    val totalTokens: Int,
    val latencyMs: Double,
)

data class DownloadedLoraAdapter(
    val id: String,
    val name: String,
    val localPath: String,
)

data class ModelDownloadUiState(
    val isDownloading: Boolean = false,
    val progress: Float = 0f,
    val error: String? = null,
    val isDownloaded: Boolean = false,
)

data class LoraDownloadUiState(
    val isDownloading: Boolean = false,
    val progress: Float = 0f,
    val error: String? = null,
    /** Path of the last successfully downloaded LoRA file */
    val downloadedPath: String? = null,
)

data class LoraUiState(
    val modelPath: String? = null,
    val modelLoaded: Boolean = false,
    val modelLoading: Boolean = false,
    val loraAdapters: List<LoRAAdapterInfo> = emptyList(),
    val question: String = "",
    val answer: String = "",
    val isGenerating: Boolean = false,
    val metrics: GenerationMetrics? = null,
    val error: String? = null,
    val modelDownload: ModelDownloadUiState = ModelDownloadUiState(),
    val loraDownload: LoraDownloadUiState = LoraDownloadUiState(),
    val catalogAdapters: List<LoraAdapterEntry> = emptyList(),
    val downloadedAdapters: List<DownloadedLoraAdapter> = emptyList(),
    val samplePrompts: List<String> = emptyList(),
)

data class BaseModelEntry(
    val id: String,
    val name: String,
    val description: String,
    val url: String,
    val framework: InferenceFramework,
)

val BASE_MODEL = BaseModelEntry(
    id = "LiquidAI-LFM2-350M-Q4_K_M",
    name = "LiquidAI LFM2-350M (Q4_K_M)",
    description = "Compact 350M language model, quantized Q4_K_M",
    url = "https://huggingface.co/Void2377/Qwen/resolve/main/LFM2-350M/LiquidAI_LFM2-350M-Q4_K_M.gguf?download=true",
    framework = InferenceFramework.LLAMA_CPP,
)

class LoraViewModel : ViewModel() {

    companion object {
        private const val TAG = "LoraVM"
    }

    private val _uiState = MutableStateFlow(LoraUiState())
    val uiState: StateFlow<LoraUiState> = _uiState.asStateFlow()

    private var generationJob: Job? = null
    private var downloadJob: Job? = null

    init {
        loadCatalog()
        scanDownloadedAdapters()
    }

    fun updateQuestion(text: String) {
        _uiState.update { it.copy(question = text) }
    }

    fun selectSamplePrompt(prompt: String) {
        _uiState.update { it.copy(question = prompt) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun loadCatalog() {
        val adapters = RunAnywhere.availableLoraAdapters()
        _uiState.update { it.copy(catalogAdapters = adapters) }
    }

    fun downloadLoraFromUrl(url: String, filename: String) {
        val sanitizedFilename = if (filename.endsWith(".gguf")) filename else "$filename.gguf"
        downloadJob?.cancel()
        downloadJob = viewModelScope.launch {
            _uiState.update {
                it.copy(loraDownload = LoraDownloadUiState(isDownloading = true))
            }
            try {
                RunAnywhere.downloadLoraAdapter(url, sanitizedFilename).collect { progress ->
                    _uiState.update {
                        it.copy(
                            loraDownload = it.loraDownload.copy(
                                progress = progress.progress,
                                error = progress.error,
                                isDownloading = progress.state == LoraDownloadState.DOWNLOADING ||
                                    progress.state == LoraDownloadState.PENDING,
                                downloadedPath = progress.localPath,
                            ),
                        )
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "LoRA download failed: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        loraDownload = LoraDownloadUiState(
                            error = "Download failed: ${e.message}",
                        ),
                    )
                }
            }
        }
    }

    fun downloadLoraFromCatalog(entry: LoraAdapterEntry) {
        downloadJob?.cancel()
        downloadJob = viewModelScope.launch {
            _uiState.update {
                it.copy(loraDownload = LoraDownloadUiState(isDownloading = true))
            }
            try {
                RunAnywhere.downloadLoraFromCatalog(entry).collect { progress ->
                    _uiState.update {
                        it.copy(
                            loraDownload = it.loraDownload.copy(
                                progress = progress.progress,
                                error = progress.error,
                                isDownloading = progress.state == LoraDownloadState.DOWNLOADING ||
                                    progress.state == LoraDownloadState.PENDING,
                                downloadedPath = progress.localPath,
                            ),
                        )
                    }

                    // When download completes, add to downloaded adapters list
                    if (progress.state == LoraDownloadState.COMPLETED && progress.localPath != null) {
                        addDownloadedAdapter(entry.id, entry.name, progress.localPath!!)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "LoRA catalog download failed: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        loraDownload = LoraDownloadUiState(
                            error = "Download failed: ${e.message}",
                        ),
                    )
                }
            }
        }
    }

    fun clearDownloadState() {
        _uiState.update { it.copy(loraDownload = LoraDownloadUiState()) }
    }

    fun downloadBaseModel() {
        downloadJob?.cancel()
        downloadJob = viewModelScope.launch {
            _uiState.update {
                it.copy(modelDownload = ModelDownloadUiState(isDownloading = true))
            }
            try {
                // Register the model in the SDK
                RunAnywhere.registerModel(
                    id = BASE_MODEL.id,
                    name = BASE_MODEL.name,
                    url = BASE_MODEL.url,
                    framework = BASE_MODEL.framework,
                )

                // Download and collect progress
                RunAnywhere.downloadModel(BASE_MODEL.id).collect { progress ->
                    _uiState.update {
                        it.copy(
                            modelDownload = it.modelDownload.copy(
                                progress = progress.progress,
                                error = progress.error,
                                isDownloading = progress.state == DownloadState.DOWNLOADING ||
                                    progress.state == DownloadState.PENDING ||
                                    progress.state == DownloadState.EXTRACTING,
                                isDownloaded = progress.state == DownloadState.COMPLETED,
                            ),
                        )
                    }

                    // Auto-load model on completion
                    if (progress.state == DownloadState.COMPLETED) {
                        loadModelById(BASE_MODEL.id)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Model download failed: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        modelDownload = ModelDownloadUiState(
                            error = "Download failed: ${e.message}",
                        ),
                    )
                }
            }
        }
    }

    fun loadModelById(modelId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(modelLoading = true, error = null) }
            try {
                // Unload existing model if loaded
                if (RunAnywhere.isLLMModelLoaded()) {
                    RunAnywhere.unloadLLMModel()
                }

                withContext(Dispatchers.IO) {
                    RunAnywhere.loadLLMModel(modelId)
                }

                _uiState.update {
                    it.copy(
                        modelPath = modelId,
                        modelLoaded = true,
                        modelLoading = false,
                        loraAdapters = emptyList(),
                    )
                }
                Log.i(TAG, "Model loaded: $modelId")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load model: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        modelLoading = false,
                        error = "Failed to load model: ${e.message}",
                    )
                }
            }
        }
    }

    fun loadModel(path: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(modelLoading = true, error = null) }
            try {
                // Unload existing model if loaded
                if (RunAnywhere.isLLMModelLoaded()) {
                    RunAnywhere.unloadLLMModel()
                }

                // Generate a model ID from filename
                val filename = path.substringAfterLast('/')
                val modelId = filename.removeSuffix(".gguf")

                // Register the model in the SDK registry
                RunAnywhere.registerModel(
                    id = modelId,
                    name = filename,
                    url = "file://$path",
                    framework = InferenceFramework.LLAMA_CPP,
                )

                // Tell the C++ registry the file is already local at this path
                CppBridgeModelRegistry.updateDownloadStatus(modelId, path)

                // Load the model
                withContext(Dispatchers.IO) {
                    RunAnywhere.loadLLMModel(modelId)
                }

                _uiState.update {
                    it.copy(
                        modelPath = path,
                        modelLoaded = true,
                        modelLoading = false,
                        loraAdapters = emptyList(),
                    )
                }
                Log.i(TAG, "Model loaded: $filename")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load model: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        modelLoading = false,
                        error = "Failed to load model: ${e.message}",
                    )
                }
            }
        }
    }

    fun loadLoraAdapter(path: String, scale: Float) {
        viewModelScope.launch {
            _uiState.update { it.copy(error = null) }
            try {
                // Check compatibility before loading
                val compat = withContext(Dispatchers.IO) {
                    RunAnywhere.checkLoraCompatibility(path)
                }
                if (!compat.isCompatible) {
                    _uiState.update { it.copy(error = "Incompatible LoRA: ${compat.error}") }
                    return@launch
                }

                withContext(Dispatchers.IO) {
                    RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path = path, scale = scale))
                }
                refreshAdapters()

                // Look up prompt template for this adapter and set sample prompts
                val catalogId = findCatalogIdForPath(path)
                val template = catalogId?.let { loraPromptTemplates[it] }
                _uiState.update {
                    it.copy(
                        samplePrompts = template?.samplePrompts ?: emptyList(),
                        question = template?.samplePrompts?.firstOrNull() ?: it.question,
                    )
                }

                Log.i(TAG, "LoRA adapter loaded: ${path.substringAfterLast('/')} (scale=$scale)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load LoRA adapter: ${e.message}", e)
                _uiState.update { it.copy(error = "Failed to load LoRA: ${e.message}") }
            }
        }
    }

    fun removeLoraAdapter(path: String) {
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    RunAnywhere.removeLoraAdapter(path)
                }
                refreshAdapters()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = "Failed to remove LoRA: ${e.message}") }
            }
        }
    }

    fun clearLoraAdapters() {
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    RunAnywhere.clearLoraAdapters()
                }
                _uiState.update { it.copy(loraAdapters = emptyList(), samplePrompts = emptyList()) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = "Failed to clear LoRA: ${e.message}") }
            }
        }
    }

    fun askQuestion() {
        val question = _uiState.value.question.trim()
        if (question.isEmpty()) return
        if (!_uiState.value.modelLoaded) {
            _uiState.update { it.copy(error = "Load a model first") }
            return
        }

        generationJob?.cancel()
        generationJob = viewModelScope.launch {
            _uiState.update {
                it.copy(
                    answer = "",
                    isGenerating = true,
                    metrics = null,
                    error = null,
                )
            }

            try {
                val result = withContext(Dispatchers.IO) {
                    RunAnywhere.generateStreamWithMetrics(
                        prompt = question,
                        options = LLMGenerationOptions(
                            maxTokens = 1024,
                            temperature = 0.7f,
                        ),
                    )
                }

                // Collect streaming tokens
                result.stream.collect { token ->
                    _uiState.update { it.copy(answer = it.answer + token) }
                }

                // Get final metrics
                val finalResult = result.result.await()
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        metrics = GenerationMetrics(
                            tokensPerSecond = finalResult.tokensPerSecond,
                            totalTokens = finalResult.tokensUsed,
                            latencyMs = finalResult.latencyMs,
                        ),
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Generation failed: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        error = "Generation failed: ${e.message}",
                    )
                }
            }
        }
    }

    fun cancelGeneration() {
        generationJob?.cancel()
        RunAnywhere.cancelGeneration()
        _uiState.update { it.copy(isGenerating = false) }
    }

    private suspend fun refreshAdapters() {
        try {
            val adapters = withContext(Dispatchers.IO) {
                RunAnywhere.getLoadedLoraAdapters()
            }
            _uiState.update { it.copy(loraAdapters = adapters) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to refresh adapters: ${e.message}", e)
        }
    }

    private fun scanDownloadedAdapters() {
        viewModelScope.launch {
            try {
                val loraDir = withContext(Dispatchers.IO) {
                    File(CppBridgeModelPaths.getModelsDirectory(), "lora")
                }
                if (!loraDir.exists()) return@launch

                val catalogEntries = LoraAdapterCatalog.adapters
                val downloaded = withContext(Dispatchers.IO) {
                    loraDir.listFiles { file -> file.extension == "gguf" }
                        ?.mapNotNull { file ->
                            val catalogEntry = catalogEntries.find { it.filename == file.name }
                            if (catalogEntry != null) {
                                DownloadedLoraAdapter(
                                    id = catalogEntry.id,
                                    name = catalogEntry.name,
                                    localPath = file.absolutePath,
                                )
                            } else {
                                // Non-catalog LoRA file
                                DownloadedLoraAdapter(
                                    id = file.nameWithoutExtension,
                                    name = file.nameWithoutExtension,
                                    localPath = file.absolutePath,
                                )
                            }
                        } ?: emptyList()
                }

                _uiState.update { it.copy(downloadedAdapters = downloaded) }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to scan downloaded adapters: ${e.message}", e)
            }
        }
    }

    private fun addDownloadedAdapter(id: String, name: String, localPath: String) {
        _uiState.update { state ->
            val existing = state.downloadedAdapters.any { it.id == id }
            if (existing) {
                state
            } else {
                state.copy(
                    downloadedAdapters = state.downloadedAdapters + DownloadedLoraAdapter(
                        id = id,
                        name = name,
                        localPath = localPath,
                    ),
                )
            }
        }
    }

    /**
     * Find the catalog adapter ID for a given file path by matching filenames.
     */
    private fun findCatalogIdForPath(path: String): String? {
        val filename = path.substringAfterLast('/')
        return LoraAdapterCatalog.adapters.find { it.filename == filename }?.id
    }
}
