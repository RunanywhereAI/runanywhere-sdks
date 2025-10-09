package com.runanywhere.runanywhereai.presentation.models

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.models.ModelInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * ViewModel for Model Selection Bottom Sheet
 * Matches iOS ModelListViewModel functionality
 *
 * Key difference from ModelsViewModel:
 * - NO MOCK DATA - calls SDK APIs directly
 * - Matches iOS implementation exactly
 */
class ModelSelectionViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(ModelSelectionUiState())
    val uiState: StateFlow<ModelSelectionUiState> = _uiState.asStateFlow()

    init {
        loadDeviceInfo()
        loadModelsAndFrameworks()
    }

    private fun loadDeviceInfo() {
        viewModelScope.launch {
            val deviceInfo = DeviceInfo(
                model = Build.MODEL,
                processor = Build.HARDWARE,
                androidVersion = "API ${Build.VERSION.SDK_INT}",
                cores = Runtime.getRuntime().availableProcessors()
            )
            _uiState.update { it.copy(deviceInfo = deviceInfo) }
        }
    }

    /**
     * Load models from SDK - matches iOS ModelListViewModel.loadModels()
     * NO MOCK DATA - calls RunAnywhere.availableModels() directly
     */
    private fun loadModelsAndFrameworks() {
        viewModelScope.launch {
            try {
                // Call SDK to get available models - matching iOS
                val models = RunAnywhere.availableModels()

                // Extract unique frameworks from models (convert enum to string)
                val frameworks = models
                    .flatMap { it.compatibleFrameworks.map { fw -> fw.toString() } }
                    .distinct()
                    .sorted()

                _uiState.update {
                    it.copy(
                        models = models,
                        frameworks = frameworks,
                        isLoading = false,
                        error = null
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load models"
                    )
                }
            }
        }
    }

    fun toggleFramework(framework: String) {
        _uiState.update {
            it.copy(
                expandedFramework = if (it.expandedFramework == framework) null else framework
            )
        }
    }

    /**
     * Download model with progress - matches iOS downloadModel
     */
    fun downloadModel(modelId: String) {
        viewModelScope.launch {
            try {
                _uiState.update {
                    it.copy(
                        selectedModelId = modelId,
                        isLoadingModel = true,
                        loadingProgress = "Starting download..."
                    )
                }

                // Call SDK download API with progress
                RunAnywhere.downloadModel(modelId).collect { progress ->
                    _uiState.update {
                        it.copy(
                            loadingProgress = "Downloading: ${(progress * 100).toInt()}%"
                        )
                    }
                }

                // Reload models after download completes
                loadModelsAndFrameworks()

                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        selectedModelId = null,
                        loadingProgress = ""
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        selectedModelId = null,
                        loadingProgress = "",
                        error = e.message ?: "Download failed"
                    )
                }
            }
        }
    }

    /**
     * Select and load model - matches iOS selectAndLoadModel
     */
    suspend fun selectModel(modelId: String) {
        try {
            _uiState.update {
                it.copy(
                    selectedModelId = modelId,
                    isLoadingModel = true,
                    loadingProgress = "Loading model into memory..."
                )
            }

            // Call SDK to load model - matching iOS
            RunAnywhere.loadModel(modelId)

            _uiState.update {
                it.copy(
                    loadingProgress = "Model loaded successfully!",
                    isLoadingModel = false,
                    selectedModelId = null
                )
            }
        } catch (e: Exception) {
            _uiState.update {
                it.copy(
                    isLoadingModel = false,
                    selectedModelId = null,
                    loadingProgress = "",
                    error = e.message ?: "Failed to load model"
                )
            }
        }
    }
}

/**
 * UI State for Model Selection Bottom Sheet
 */
data class ModelSelectionUiState(
    val deviceInfo: DeviceInfo? = null,
    val models: List<ModelInfo> = emptyList(),
    val frameworks: List<String> = emptyList(),
    val expandedFramework: String? = null,
    val selectedModelId: String? = null,
    val isLoading: Boolean = true,
    val isLoadingModel: Boolean = false,
    val loadingProgress: String = "",
    val error: String? = null
)
