package com.runanywhere.runanywhereai.presentation.models

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.models.collectDeviceInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.collections.find

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
            val deviceInfo = collectDeviceInfo()
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
                android.util.Log.d("ModelSelectionVM", "🔄 Loading models and frameworks...")

                // Call SDK to get available models - matching iOS
                val models = RunAnywhere.availableModels()
                android.util.Log.d("ModelSelectionVM", "📦 Fetched ${models.size} models from SDK")

                // Get registered framework providers from ModuleRegistry
                val llmProviders = com.runanywhere.sdk.core.ModuleRegistry.allLLMProviders
                val sttProviders = com.runanywhere.sdk.core.ModuleRegistry.allSTTProviders

                android.util.Log.d("ModelSelectionVM", "🔍 LLM Providers registered: ${llmProviders.size}")
                llmProviders.forEach { provider ->
                    android.util.Log.d("ModelSelectionVM", "   - ${provider.name}")
                    android.util.Log.d("ModelSelectionVM", "     framework enum: ${provider.framework}")
                    android.util.Log.d("ModelSelectionVM", "     displayName: ${provider.framework.displayName}")
                }

                // Build framework list from registered providers
                // CRITICAL: Use displayName to match UI filtering
                val frameworks = buildList {
                    // Add LLM frameworks using displayName
                    llmProviders.forEach { provider ->
                        add(provider.framework.displayName)  // e.g., "llama.cpp"
                    }
                    // Add STT frameworks
                    sttProviders.forEach { provider ->
                        add(provider.name)
                    }
                }.distinct().sorted()

                android.util.Log.d("ModelSelectionVM", "✅ Loaded ${models.size} models and ${frameworks.size} frameworks")
                android.util.Log.d("ModelSelectionVM", "📦 Frameworks: $frameworks")

                // Log each model's details
                models.forEachIndexed { index, model ->
                    android.util.Log.d("ModelSelectionVM", "📋 Model ${index + 1}: ${model.name}")
                    android.util.Log.d("ModelSelectionVM", "   - ID: ${model.id}")
                    android.util.Log.d("ModelSelectionVM", "   - Compatible Frameworks (enum): ${model.compatibleFrameworks}")
                    android.util.Log.d("ModelSelectionVM", "   - Compatible Frameworks (displayName): ${model.compatibleFrameworks.map { it.displayName }}")
                }

                _uiState.update {
                    it.copy(
                        models = models,
                        frameworks = frameworks,
                        isLoading = false,
                        error = null
                    )
                }

                android.util.Log.d("ModelSelectionVM", "🎉 UI state updated successfully")

            } catch (e: Exception) {
                android.util.Log.e("ModelSelectionVM", "❌ Failed to load models: ${e.message}", e)
                e.printStackTrace()
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
        android.util.Log.d("ModelSelectionVM", "🔀 Toggling framework: $framework")
        _uiState.update {
            it.copy(
                expandedFramework = if (it.expandedFramework == framework) null else framework
            )
        }
        android.util.Log.d("ModelSelectionVM", "   Expanded framework now: ${_uiState.value.expandedFramework}")
    }

    /**
     * Download model with progress - matches iOS downloadModel
     */
    fun downloadModel(modelId: String) {
        viewModelScope.launch {
            try {
                android.util.Log.d("ModelSelectionVM", "⬇️ Starting download for model: $modelId")

                _uiState.update {
                    it.copy(
                        selectedModelId = modelId,
                        isLoadingModel = true,
                        loadingProgress = "Starting download..."
                    )
                }

                // Call SDK download API with progress
                RunAnywhere.downloadModel(modelId).collect { progress ->
                    val progressPercent = (progress * 100).toInt()
                    android.util.Log.d("ModelSelectionVM", "📊 Download progress: $progressPercent%")

                    _uiState.update {
                        it.copy(
                            loadingProgress = "Downloading: $progressPercent%"
                        )
                    }
                }

                android.util.Log.d("ModelSelectionVM", "✅ Download complete for $modelId")

                // Small delay to ensure registry update propagates
                kotlinx.coroutines.delay(500)

                // Reload models after download completes - should now have localPath set
                android.util.Log.d("ModelSelectionVM", "🔄 Refreshing models list to get updated localPath...")
                loadModelsAndFrameworks()

                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        selectedModelId = null,
                        loadingProgress = ""
                    )
                }
            } catch (e: Exception) {
                android.util.Log.e("ModelSelectionVM", "❌ Download failed for $modelId: ${e.message}", e)
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
            android.util.Log.d("ModelSelectionVM", "🔄 Loading model into memory: $modelId")

            _uiState.update {
                it.copy(
                    selectedModelId = modelId,
                    isLoadingModel = true,
                    loadingProgress = "Loading model into memory..."
                )
            }

            // Call SDK to load model - matching iOS
            RunAnywhere.loadModel(modelId)

            android.util.Log.d("ModelSelectionVM", "✅ Model loaded successfully: $modelId")

            // Get the loaded model from the updated models list
            val loadedModel = _uiState.value.models.find { it.id == modelId }

            _uiState.update {
                it.copy(
                    loadingProgress = "Model loaded successfully!",
                    isLoadingModel = false,
                    selectedModelId = null,
                    currentModel = loadedModel  // Track the currently loaded model
                )
            }
        } catch (e: Exception) {
            android.util.Log.e("ModelSelectionVM", "❌ Failed to load model $modelId: ${e.message}", e)
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

    /**
     * Refresh models list - called after download completes
     */
    fun refreshModels() {
        loadModelsAndFrameworks()
    }
}

/**
 * UI State for Model Selection Bottom Sheet
 */
data class ModelSelectionUiState(
    val deviceInfo: com.runanywhere.sdk.models.DeviceInfo? = null,
    val models: List<ModelInfo> = emptyList(),
    val frameworks: List<String> = emptyList(),
    val expandedFramework: String? = null,
    val selectedModelId: String? = null,
    val currentModel: ModelInfo? = null,  // Currently loaded model - matches iOS
    val isLoading: Boolean = true,
    val isLoadingModel: Boolean = false,
    val loadingProgress: String = "",
    val error: String? = null
)
