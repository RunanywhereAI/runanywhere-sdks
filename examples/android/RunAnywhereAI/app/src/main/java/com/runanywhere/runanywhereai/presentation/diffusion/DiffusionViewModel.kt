package com.runanywhere.runanywhereai.presentation.diffusion

import android.graphics.Bitmap
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionModelVariant
import com.runanywhere.sdk.public.extensions.Models.DownloadState
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.availableModels
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.generateImage
import com.runanywhere.sdk.public.extensions.isDiffusionModelLoaded
import com.runanywhere.sdk.public.extensions.loadDiffusionModel
import com.runanywhere.sdk.public.extensions.unloadDiffusionModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch
import java.nio.ByteBuffer

data class DiffusionUiState(
    val status: String = "Loading models...",
    val availableModels: List<ModelInfo> = emptyList(),
    val selectedModelId: String? = null,
    val isDownloading: Boolean = false,
    val downloadProgress: Float = 0f,
    val isLoading: Boolean = false,
    val isModelLoaded: Boolean = false,
    val isGenerating: Boolean = false,
    val generatedImage: Bitmap? = null,
    val prompt: String = "A beautiful sunset over mountains, oil painting style",
    val generationTimeMs: Long = 0,
    val errorMessage: String? = null,
)

/**
 * ViewModel for diffusion image generation.
 * Uses the same SDK model management flow as LLM/STT/TTS:
 *   1. RunAnywhere.availableModels() -> filter IMAGE_GENERATION
 *   2. RunAnywhere.downloadModel(id) -> progress Flow
 *   3. RunAnywhere.loadDiffusionModel(path, id, config)
 *   4. RunAnywhere.generateImage(prompt, options)
 */
class DiffusionViewModel : ViewModel() {
    companion object {
        private const val TAG = "DiffusionVM"
    }

    private val _uiState = MutableStateFlow(DiffusionUiState())
    val uiState: StateFlow<DiffusionUiState> = _uiState.asStateFlow()

    init {
        loadAvailableModels()
    }

    // ========================================================================
    // Model Discovery (same as iOS DiffusionViewModel.loadAvailableModels)
    // ========================================================================

    fun loadAvailableModels() {
        viewModelScope.launch {
            try {
                val allModels = RunAnywhere.availableModels()
                val diffusionModels = allModels.filter {
                    it.category == ModelCategory.IMAGE_GENERATION
                }

                val selectedId = diffusionModels.firstOrNull { it.isDownloaded }?.id
                    ?: diffusionModels.firstOrNull()?.id

                _uiState.value = _uiState.value.copy(
                    availableModels = diffusionModels,
                    selectedModelId = selectedId,
                    status = if (diffusionModels.isEmpty()) {
                        "No diffusion models registered"
                    } else {
                        val downloaded = diffusionModels.count { it.isDownloaded }
                        "$downloaded/${diffusionModels.size} models downloaded"
                    },
                )

                Log.i(TAG, "Found ${diffusionModels.size} diffusion models")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load models", e)
                _uiState.value = _uiState.value.copy(
                    status = "Failed to load models",
                    errorMessage = e.message,
                )
            }
        }
    }

    fun selectModel(modelId: String) {
        _uiState.value = _uiState.value.copy(selectedModelId = modelId)
    }

    fun updatePrompt(newPrompt: String) {
        _uiState.value = _uiState.value.copy(prompt = newPrompt)
    }

    // ========================================================================
    // Model Download (same as ModelSelectionViewModel.startDownload)
    // ========================================================================

    fun downloadSelectedModel() {
        val modelId = _uiState.value.selectedModelId ?: return

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isDownloading = true,
                downloadProgress = 0f,
                status = "Starting download...",
                errorMessage = null,
            )

            RunAnywhere.downloadModel(modelId)
                .catch { e ->
                    Log.e(TAG, "Download failed", e)
                    _uiState.value = _uiState.value.copy(
                        isDownloading = false,
                        status = "Download failed",
                        errorMessage = e.message,
                    )
                }
                .collect { progress ->
                    val percent = (progress.progress * 100).toInt()
                    _uiState.value = _uiState.value.copy(
                        downloadProgress = progress.progress,
                        status = when (progress.state) {
                            DownloadState.DOWNLOADING -> "Downloading... $percent%"
                            DownloadState.EXTRACTING -> "Extracting..."
                            DownloadState.COMPLETED -> "Download complete!"
                            DownloadState.ERROR -> "Download failed"
                            else -> "Preparing..."
                        },
                    )

                    if (progress.state == DownloadState.COMPLETED) {
                        _uiState.value = _uiState.value.copy(isDownloading = false)
                        loadAvailableModels()
                    }
                    if (progress.state == DownloadState.ERROR) {
                        _uiState.value = _uiState.value.copy(
                            isDownloading = false,
                            errorMessage = progress.error,
                        )
                    }
                }
        }
    }

    // ========================================================================
    // Model Loading (same pattern as iOS DiffusionViewModel.loadSelectedModel)
    // ========================================================================

    fun loadSelectedModel() {
        val modelId = _uiState.value.selectedModelId ?: return
        val model = _uiState.value.availableModels.find { it.id == modelId } ?: return
        val localPath = model.localPath ?: run {
            _uiState.value = _uiState.value.copy(errorMessage = "Model not downloaded")
            return
        }

        viewModelScope.launch(Dispatchers.IO) {
            _uiState.value = _uiState.value.copy(
                isLoading = true,
                status = "Loading model...",
                errorMessage = null,
            )

            try {
                val config = DiffusionConfiguration(
                    modelVariant = DiffusionModelVariant.SD_1_5,
                    enableSafetyChecker = false,
                    reduceMemory = true,
                    preferredFramework = com.runanywhere.sdk.core.types.InferenceFramework.SDCPP,
                )

                RunAnywhere.loadDiffusionModel(
                    modelPath = localPath,
                    modelId = model.id,
                    modelName = model.name,
                    configuration = config,
                )

                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    isModelLoaded = true,
                    status = "Model loaded! Ready to generate.",
                )
                Log.i(TAG, "Model loaded: ${model.name}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load model", e)
                _uiState.value = _uiState.value.copy(
                    isLoading = false,
                    status = "Load failed",
                    errorMessage = e.message,
                )
            }
        }
    }

    // ========================================================================
    // Image Generation
    // ========================================================================

    fun generateImage() {
        if (!_uiState.value.isModelLoaded) {
            _uiState.value = _uiState.value.copy(errorMessage = "Load a model first")
            return
        }

        val prompt = _uiState.value.prompt
        if (prompt.isBlank()) {
            _uiState.value = _uiState.value.copy(errorMessage = "Enter a prompt")
            return
        }

        viewModelScope.launch(Dispatchers.IO) {
            _uiState.value = _uiState.value.copy(
                isGenerating = true,
                status = "Generating image...",
                errorMessage = null,
                generatedImage = null,
            )

            try {
                val options = DiffusionGenerationOptions.withVariantDefaults(
                    prompt = prompt,
                    variant = DiffusionModelVariant.SD_1_5,
                )

                val result = RunAnywhere.generateImage(prompt, options)

                val bitmap = Bitmap.createBitmap(result.width, result.height, Bitmap.Config.ARGB_8888)
                bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(result.imageData))

                _uiState.value = _uiState.value.copy(
                    isGenerating = false,
                    generatedImage = bitmap,
                    generationTimeMs = result.generationTimeMs,
                    status = "Generated in ${result.generationTimeMs / 1000}s",
                )
                Log.i(TAG, "Image generated: ${result.width}x${result.height} in ${result.generationTimeMs}ms")
            } catch (e: Exception) {
                Log.e(TAG, "Generation failed", e)
                _uiState.value = _uiState.value.copy(
                    isGenerating = false,
                    status = "Generation failed",
                    errorMessage = e.message,
                )
            }
        }
    }

    fun unloadModel() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                RunAnywhere.unloadDiffusionModel()
                _uiState.value = _uiState.value.copy(
                    isModelLoaded = false,
                    generatedImage = null,
                    status = "Model unloaded",
                )
            } catch (e: Exception) {
                Log.e(TAG, "Unload failed", e)
            }
        }
    }
}
