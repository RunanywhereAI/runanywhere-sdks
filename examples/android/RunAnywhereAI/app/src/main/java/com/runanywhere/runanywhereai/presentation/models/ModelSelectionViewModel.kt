package com.runanywhere.runanywhereai.presentation.models

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.models.collectDeviceInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelSelectionContext
import com.runanywhere.sdk.models.enums.supportedModalities
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * ViewModel for Model Selection Bottom Sheet
 * Matches iOS ModelListViewModel functionality with context-aware filtering
 *
 * Reference: iOS ModelSelectionSheet.swift
 */
class ModelSelectionViewModel(
    private val context: ModelSelectionContext = ModelSelectionContext.LLM
) : ViewModel() {

    private val _uiState = MutableStateFlow(ModelSelectionUiState(context = context))
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
     * Load models from SDK with context-aware filtering
     * Matches iOS ModelListViewModel.loadModels() with ModelSelectionContext filtering
     */
    private fun loadModelsAndFrameworks() {
        viewModelScope.launch {
            try {
                android.util.Log.d("ModelSelectionVM", "🔄 Loading models and frameworks for context: $context")

                // Call SDK to get available models
                val allModels = RunAnywhere.availableModels()
                android.util.Log.d("ModelSelectionVM", "📦 Fetched ${allModels.size} total models from SDK")

                // Filter models by context - matches iOS relevantCategories filtering
                val filteredModels = allModels.filter { model ->
                    context.isCategoryRelevant(model.category)
                }
                android.util.Log.d("ModelSelectionVM", "📦 Filtered to ${filteredModels.size} models for context $context")

                // Get registered framework providers from ModuleRegistry
                val llmProviders = com.runanywhere.sdk.core.ModuleRegistry.allLLMProviders
                val sttProviders = com.runanywhere.sdk.core.ModuleRegistry.allSTTProviders
                val ttsProviders = com.runanywhere.sdk.core.ModuleRegistry.allTTSProviders

                android.util.Log.d("ModelSelectionVM", "🔍 LLM Providers: ${llmProviders.size}, STT Providers: ${sttProviders.size}, TTS Providers: ${ttsProviders.size}")

                // Build framework list from registered providers - filtered by context
                val allRegisteredFrameworks = mutableSetOf<LLMFramework>()

                // Add LLM frameworks
                llmProviders.forEach { provider ->
                    allRegisteredFrameworks.add(provider.framework)
                }
                // Add STT frameworks
                sttProviders.forEach { provider ->
                    allRegisteredFrameworks.add(provider.framework)
                }
                // Add TTS frameworks
                ttsProviders.forEach { provider ->
                    allRegisteredFrameworks.add(provider.framework)
                }

                // Filter frameworks by context - matches iOS shouldShowFramework logic
                var relevantFrameworks = allRegisteredFrameworks.filter { framework ->
                    context.isFrameworkRelevant(framework)
                }.sortedBy { it.displayName }.toMutableList()

                // For TTS context, ensure System TTS is included (matches iOS behavior)
                // iOS Reference: ModelSelectionSheet.swift line 167
                // Only add if not already present from registered TTS providers
                if (context == ModelSelectionContext.TTS && !relevantFrameworks.contains(LLMFramework.SYSTEM_TTS)) {
                    // Add System TTS at the beginning of the list
                    relevantFrameworks.add(0, LLMFramework.SYSTEM_TTS)
                    android.util.Log.d("ModelSelectionVM", "📱 Added System TTS for TTS context (not from provider)")
                } else if (context == ModelSelectionContext.TTS && relevantFrameworks.contains(LLMFramework.SYSTEM_TTS)) {
                    // Move System TTS to the beginning if already present
                    relevantFrameworks.remove(LLMFramework.SYSTEM_TTS)
                    relevantFrameworks.add(0, LLMFramework.SYSTEM_TTS)
                    android.util.Log.d("ModelSelectionVM", "📱 System TTS already registered, moved to top")
                }

                android.util.Log.d("ModelSelectionVM", "✅ Loaded ${filteredModels.size} models and ${relevantFrameworks.size} frameworks for context $context")
                relevantFrameworks.forEach { fw ->
                    android.util.Log.d("ModelSelectionVM", "   Framework: ${fw.displayName} (${fw.name})")
                }

                // Log filtered models
                filteredModels.forEachIndexed { index, model ->
                    android.util.Log.d("ModelSelectionVM", "📋 Model ${index + 1}: ${model.name}")
                    android.util.Log.d("ModelSelectionVM", "   - Category: ${model.category}")
                    android.util.Log.d("ModelSelectionVM", "   - Frameworks: ${model.compatibleFrameworks.map { it.displayName }}")
                }

                _uiState.update {
                    it.copy(
                        models = filteredModels,
                        frameworks = relevantFrameworks,
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

    /**
     * Toggle framework expansion - now uses LLMFramework enum
     */
    fun toggleFramework(framework: LLMFramework) {
        android.util.Log.d("ModelSelectionVM", "🔀 Toggling framework: ${framework.displayName}")
        _uiState.update {
            it.copy(
                expandedFramework = if (it.expandedFramework == framework) null else framework
            )
        }
        android.util.Log.d("ModelSelectionVM", "   Expanded framework now: ${_uiState.value.expandedFramework?.displayName}")
    }

    /**
     * Get models for a specific framework
     * Matches iOS filtering logic
     */
    fun getModelsForFramework(framework: LLMFramework): List<ModelInfo> {
        return _uiState.value.models.filter { model ->
            model.compatibleFrameworks.contains(framework) ||
                    model.preferredFramework == framework
        }
    }

    /**
     * Download model with progress
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
     * Select and load model - context-aware loading
     * Matches iOS context-based loading (llm -> loadModel, stt -> loadSTTModel, tts -> loadTTSModel)
     */
    suspend fun selectModel(modelId: String) {
        try {
            android.util.Log.d("ModelSelectionVM", "🔄 Loading model into memory: $modelId (context: $context)")

            _uiState.update {
                it.copy(
                    selectedModelId = modelId,
                    isLoadingModel = true,
                    loadingProgress = "Loading model into memory..."
                )
            }

            // Context-aware model loading - matches iOS exactly
            when (context) {
                ModelSelectionContext.LLM -> {
                    RunAnywhere.loadModel(modelId)
                }
                ModelSelectionContext.STT -> {
                    RunAnywhere.loadSTTModel(modelId)
                }
                ModelSelectionContext.TTS -> {
                    RunAnywhere.loadTTSModel(modelId)
                }
                ModelSelectionContext.VOICE -> {
                    // For voice context, determine from model category
                    val model = _uiState.value.models.find { it.id == modelId }
                    when (model?.category) {
                        com.runanywhere.sdk.models.enums.ModelCategory.SPEECH_RECOGNITION -> RunAnywhere.loadSTTModel(modelId)
                        com.runanywhere.sdk.models.enums.ModelCategory.SPEECH_SYNTHESIS -> RunAnywhere.loadTTSModel(modelId)
                        else -> RunAnywhere.loadModel(modelId)
                    }
                }
            }

            android.util.Log.d("ModelSelectionVM", "✅ Model loaded successfully: $modelId")

            // Get the loaded model
            val loadedModel = _uiState.value.models.find { it.id == modelId }

            _uiState.update {
                it.copy(
                    loadingProgress = "Model loaded successfully!",
                    isLoadingModel = false,
                    selectedModelId = null,
                    currentModel = loadedModel
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
     * Refresh models list
     */
    fun refreshModels() {
        loadModelsAndFrameworks()
    }

    /**
     * Set loading model state
     * Used for System TTS which doesn't require model download
     */
    fun setLoadingModel(isLoading: Boolean) {
        _uiState.update {
            it.copy(isLoadingModel = isLoading)
        }
    }

    /**
     * Factory for creating ViewModel with context parameter
     */
    class Factory(private val context: ModelSelectionContext) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(ModelSelectionViewModel::class.java)) {
                return ModelSelectionViewModel(context) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class")
        }
    }
}

/**
 * UI State for Model Selection Bottom Sheet
 * Now uses LLMFramework enum instead of strings
 */
data class ModelSelectionUiState(
    val context: ModelSelectionContext = ModelSelectionContext.LLM,
    val deviceInfo: DeviceInfo? = null,
    val models: List<ModelInfo> = emptyList(),
    val frameworks: List<LLMFramework> = emptyList(),
    val expandedFramework: LLMFramework? = null,
    val selectedModelId: String? = null,
    val currentModel: ModelInfo? = null,
    val isLoading: Boolean = true,
    val isLoadingModel: Boolean = false,
    val loadingProgress: String = "",
    val error: String? = null
)
