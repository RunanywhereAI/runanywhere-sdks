package com.runanywhere.runanywhereai.presentation.diffusion

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.EventCategory
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionModelVariant
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionResult
import com.runanywhere.sdk.public.extensions.cancelDiffusionGeneration
import com.runanywhere.sdk.public.extensions.configureDiffusion
import com.runanywhere.sdk.public.extensions.currentDiffusionModelId
import com.runanywhere.sdk.public.extensions.generateImageWithOptions
import com.runanywhere.sdk.public.extensions.isDiffusionModelLoadedSync
import com.runanywhere.sdk.public.extensions.loadDiffusionModel
import com.runanywhere.sdk.public.extensions.unloadDiffusionModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Diffusion UI State
 */
data class DiffusionUiState(
    val isModelLoaded: Boolean = false,
    val selectedFramework: InferenceFramework? = null,
    val selectedModelName: String? = null,
    val selectedModelId: String? = null,
    val backendType: String = "", // "CoreML" or "ONNX"
    val prompt: String = "A serene mountain landscape at sunset with golden light",
    val negativePrompt: String = "",
    val isGenerating: Boolean = false,
    val progress: Float = 0f,
    val currentStep: Int = 0,
    val totalSteps: Int = 0,
    val statusMessage: String = "Ready",
    val errorMessage: String? = null,
    val generatedImageData: ByteArray? = null,
    val imageWidth: Int = 0,
    val imageHeight: Int = 0,
    val seedUsed: Long = 0,
    val generationTimeMs: Long = 0,
    // Generation options
    val width: Int = 512,
    val height: Int = 512,
    val steps: Int = 28,
    val guidanceScale: Float = 7.5f,
    val seed: Long = -1L,
)

/**
 * Diffusion ViewModel
 *
 * iOS Reference: DiffusionViewModel in DiffusionViewModel.swift
 *
 * This ViewModel manages:
 * - Model loading via RunAnywhere.loadDiffusionModel()
 * - Image generation via RunAnywhere.generateImageWithOptions()
 * - Progress tracking during generation
 * - Backend type display (CoreML vs ONNX)
 */
class DiffusionViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(DiffusionUiState())
    val uiState: StateFlow<DiffusionUiState> = _uiState.asStateFlow()

    private var generationJob: Job? = null

    companion object {
        private const val TAG = "DiffusionViewModel"

        val SAMPLE_PROMPTS = listOf(
            "A serene mountain landscape at sunset with golden light",
            "A futuristic city with flying cars and neon lights",
            "A cute corgi puppy wearing a tiny astronaut helmet",
            "An ancient library filled with magical floating books",
            "A cozy coffee shop on a rainy day, warm lighting",
        )
    }

    init {
        subscribeToSDKEvents()
        checkModelState()
    }

    /**
     * Subscribe to SDK events for model state changes
     */
    private fun subscribeToSDKEvents() {
        viewModelScope.launch {
            try {
                EventBus.events(EventCategory.Model).collect { event ->
                    when (event) {
                        is ModelEvent.ModelLoaded -> {
                            if (event.modelId == _uiState.value.selectedModelId) {
                                Log.d(TAG, "Diffusion model loaded: ${event.modelId}")
                                checkModelState()
                            }
                        }
                        is ModelEvent.ModelUnloaded -> {
                            if (event.modelId == _uiState.value.selectedModelId) {
                                Log.d(TAG, "Diffusion model unloaded: ${event.modelId}")
                                _uiState.update { it.copy(isModelLoaded = false) }
                            }
                        }
                        else -> {}
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error subscribing to SDK events", e)
            }
        }
    }

    /**
     * Check if a model is currently loaded
     */
    private fun checkModelState() {
        val isLoaded = RunAnywhere.isDiffusionModelLoadedSync
        val modelId = RunAnywhere.currentDiffusionModelId
        _uiState.update { state ->
            state.copy(
                isModelLoaded = isLoaded,
                selectedModelId = modelId,
            )
        }
    }

    /**
     * Called when a model is selected from the model picker
     */
    fun onModelLoaded(modelName: String, modelId: String, framework: InferenceFramework?) {
        val backendType = when {
            framework?.rawValue?.contains("CoreML", ignoreCase = true) == true -> "CoreML"
            framework?.rawValue?.contains("ONNX", ignoreCase = true) == true -> "ONNX"
            else -> framework?.displayName ?: "Unknown"
        }

        _uiState.update { state ->
            state.copy(
                isModelLoaded = true,
                selectedModelName = modelName,
                selectedModelId = modelId,
                selectedFramework = framework,
                backendType = backendType,
                statusMessage = "Model loaded ($backendType)",
                errorMessage = null,
            )
        }
        Log.i(TAG, "Model loaded: $modelName ($backendType)")
    }

    /**
     * Update prompt text
     */
    fun updatePrompt(prompt: String) {
        _uiState.update { it.copy(prompt = prompt) }
    }

    /**
     * Update negative prompt text
     */
    fun updateNegativePrompt(negativePrompt: String) {
        _uiState.update { it.copy(negativePrompt = negativePrompt) }
    }

    /**
     * Update generation parameters
     */
    fun updateGenerationParams(
        width: Int? = null,
        height: Int? = null,
        steps: Int? = null,
        guidanceScale: Float? = null,
        seed: Long? = null,
    ) {
        _uiState.update { state ->
            state.copy(
                width = width ?: state.width,
                height = height ?: state.height,
                steps = steps ?: state.steps,
                guidanceScale = guidanceScale ?: state.guidanceScale,
                seed = seed ?: state.seed,
            )
        }
    }

    /**
     * Generate an image from the current prompt
     */
    fun generateImage() {
        val state = _uiState.value

        if (state.prompt.isBlank()) {
            _uiState.update { it.copy(errorMessage = "Please enter a prompt") }
            return
        }

        if (!state.isModelLoaded) {
            _uiState.update { it.copy(errorMessage = "Please load a model first") }
            return
        }

        generationJob = viewModelScope.launch {
            try {
                _uiState.update {
                    it.copy(
                        isGenerating = true,
                        progress = 0f,
                        currentStep = 0,
                        statusMessage = "Starting generation...",
                        errorMessage = null,
                        generatedImageData = null,
                    )
                }

                val options = DiffusionGenerationOptions.textToImage(
                    prompt = state.prompt,
                    negativePrompt = state.negativePrompt,
                    width = state.width,
                    height = state.height,
                    steps = state.steps,
                    guidanceScale = state.guidanceScale,
                    seed = state.seed,
                )

                Log.d(TAG, "Starting generation: ${state.prompt.take(50)}...")

                val result = withContext(Dispatchers.IO) {
                    RunAnywhere.generateImageWithOptions(options)
                }

                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        progress = 1f,
                        currentStep = state.steps,
                        totalSteps = state.steps,
                        statusMessage = "Done (${result.generationTimeMs}ms)",
                        generatedImageData = result.imageData,
                        imageWidth = result.width,
                        imageHeight = result.height,
                        seedUsed = result.seedUsed,
                        generationTimeMs = result.generationTimeMs,
                    )
                }

                Log.i(TAG, "Generation complete: ${result.width}x${result.height}, ${result.generationTimeMs}ms")

            } catch (e: Exception) {
                Log.e(TAG, "Generation failed", e)
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        statusMessage = "Failed",
                        errorMessage = "Generation failed: ${e.message}",
                    )
                }
            }
        }
    }

    /**
     * Cancel ongoing generation
     */
    fun cancelGeneration() {
        viewModelScope.launch {
            try {
                generationJob?.cancel()
                RunAnywhere.cancelDiffusionGeneration()
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        statusMessage = "Cancelled",
                    )
                }
                Log.d(TAG, "Generation cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "Error cancelling generation", e)
            }
        }
    }

    /**
     * Unload the current model
     */
    fun unloadModel() {
        viewModelScope.launch {
            try {
                RunAnywhere.unloadDiffusionModel()
                _uiState.update {
                    it.copy(
                        isModelLoaded = false,
                        selectedModelName = null,
                        selectedModelId = null,
                        backendType = "",
                        statusMessage = "Model unloaded",
                    )
                }
                Log.d(TAG, "Model unloaded")
            } catch (e: Exception) {
                Log.e(TAG, "Error unloading model", e)
            }
        }
    }

    /**
     * Clear the error message
     */
    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    /**
     * Clear the generated image
     */
    fun clearImage() {
        _uiState.update {
            it.copy(
                generatedImageData = null,
                imageWidth = 0,
                imageHeight = 0,
            )
        }
    }

    override fun onCleared() {
        super.onCleared()
        generationJob?.cancel()
    }
}
