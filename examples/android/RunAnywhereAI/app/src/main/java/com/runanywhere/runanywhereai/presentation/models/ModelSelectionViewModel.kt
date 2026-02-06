package com.runanywhere.runanywhereai.presentation.models

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.models.collectDeviceInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.extensions.availableModels
import com.runanywhere.sdk.public.extensions.currentLLMModelId
import com.runanywhere.sdk.public.extensions.currentSTTModelId
import com.runanywhere.sdk.public.extensions.currentTTSVoiceId
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * ViewModel for Model Selection Bottom Sheet
 * Matches iOS ModelListViewModel functionality with context-aware filtering
 *
 * Reference: iOS ModelSelectionSheet.swift
 */
class ModelSelectionViewModel(
    private val context: ModelSelectionContext = ModelSelectionContext.LLM,
) : ViewModel() {
    private val _uiState = MutableStateFlow(ModelSelectionUiState(context = context))
    val uiState: StateFlow<ModelSelectionUiState> = _uiState.asStateFlow()

    init {
        loadDeviceInfo()
        loadModelsAndFrameworks()
        subscribeToDownloadEvents()
    }

    /**
     * Subscribe to SDK download progress events to update UI
     */
    private fun subscribeToDownloadEvents() {
        viewModelScope.launch {
            Log.d(TAG, "📡 Subscribed to download progress events")
            EventBus.events
                .filterIsInstance<ModelEvent>()
                .collect { event ->
                    when (event.eventType) {
                        ModelEvent.ModelEventType.DOWNLOAD_PROGRESS -> {
                            val progressPercent = ((event.progress ?: 0f) * 100).toInt()
                            Log.d(TAG, "📊 Download progress: ${event.modelId} - $progressPercent%")
                            _uiState.update {
                                it.copy(loadingProgress = "Downloading... $progressPercent%")
                            }
                        }
                        ModelEvent.ModelEventType.DOWNLOAD_COMPLETED -> {
                            Log.d(TAG, "✅ Download completed: ${event.modelId}")
                            loadModelsAndFrameworks() // Refresh models list
                        }
                        ModelEvent.ModelEventType.DOWNLOAD_FAILED -> {
                            Log.e(TAG, "❌ Download failed: ${event.modelId} - ${event.error}")
                            _uiState.update {
                                it.copy(
                                    isLoadingModel = false,
                                    loadingProgress = "",
                                    error = event.error ?: "Download failed",
                                )
                            }
                        }
                        else -> {}
                    }
                }
        }
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
                Log.d(TAG, "🔄 Loading models and frameworks for context: $context")

                // Call SDK to get available models
                val allModels = RunAnywhere.availableModels()
                Log.d(TAG, "📦 Fetched ${allModels.size} total models from SDK")

                // Filter models by context - matches iOS relevantCategories filtering
                val filteredModels =
                    allModels.filter { model ->
                        isModelRelevantForContext(model.category, context)
                    }
                Log.d(TAG, "📦 Filtered to ${filteredModels.size} models for context $context")

                // Extract unique frameworks from filtered models
                val relevantFrameworks =
                    filteredModels
                        .map { it.framework }
                        .toSet()
                        .sortedBy { it.displayName }
                        .toMutableList()

                // For TTS context, ensure System TTS is included (matches iOS behavior)
                if (context == ModelSelectionContext.TTS && !relevantFrameworks.contains(InferenceFramework.SYSTEM_TTS)) {
                    relevantFrameworks.add(0, InferenceFramework.SYSTEM_TTS)
                    Log.d(TAG, "📱 Added System TTS for TTS context")
                }

                Log.d(TAG, "✅ Loaded ${filteredModels.size} models and ${relevantFrameworks.size} frameworks")
                relevantFrameworks.forEach { fw ->
                    Log.d(TAG, "   Framework: ${fw.displayName}")
                }

                // Sync with currently loaded model from SDK
                // This ensures already-loaded models show as "Loaded" in the sheet
                val currentLoadedModelId = getCurrentLoadedModelIdForContext()
                val currentLoadedModel =
                    if (currentLoadedModelId != null) {
                        filteredModels.find { it.id == currentLoadedModelId }
                    } else {
                        null
                    }

                if (currentLoadedModel != null) {
                    Log.d(TAG, "✅ Found currently loaded model for context $context: ${currentLoadedModel.id}")
                }

                _uiState.update {
                    it.copy(
                        models = filteredModels,
                        frameworks = relevantFrameworks,
                        isLoading = false,
                        error = null,
                        currentModel = currentLoadedModel,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to load models: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = e.message ?: "Failed to load models",
                    )
                }
            }
        }
    }

    /**
     * Get the currently loaded model ID for this context from the SDK.
     * This syncs the selection sheet with what's actually loaded in memory.
     * Matches iOS's pattern of querying currentModelId from CppBridge.
     */
    private fun getCurrentLoadedModelIdForContext(): String? {
        return when (context) {
            ModelSelectionContext.LLM -> RunAnywhere.currentLLMModelId
            ModelSelectionContext.STT -> RunAnywhere.currentSTTModelId
            ModelSelectionContext.TTS -> RunAnywhere.currentTTSVoiceId
            ModelSelectionContext.VOICE -> {
                // For voice context, we could return any of the three
                // but typically the voice sheet doesn't auto-select
                null
            }
        }
    }

    /**
     * Check if a model category is relevant for the current selection context
     */
    private fun isModelRelevantForContext(
        category: ModelCategory,
        ctx: ModelSelectionContext,
    ): Boolean {
        return when (ctx) {
            ModelSelectionContext.LLM -> category == ModelCategory.LANGUAGE
            ModelSelectionContext.STT -> category == ModelCategory.SPEECH_RECOGNITION
            ModelSelectionContext.TTS -> category == ModelCategory.SPEECH_SYNTHESIS
            ModelSelectionContext.VOICE ->
                category in
                    listOf(
                        ModelCategory.LANGUAGE,
                        ModelCategory.SPEECH_RECOGNITION,
                        ModelCategory.SPEECH_SYNTHESIS,
                    )
        }
    }

    /**
     * Toggle framework expansion
     */
    fun toggleFramework(framework: InferenceFramework) {
        Log.d(TAG, "🔀 Toggling framework: ${framework.displayName}")
        _uiState.update {
            it.copy(
                expandedFramework = if (it.expandedFramework == framework) null else framework,
            )
        }
    }

    /**
     * Get models for a specific framework
     */
    fun getModelsForFramework(framework: InferenceFramework): List<ModelInfo> {
        return _uiState.value.models.filter { model ->
            model.framework == framework
        }
    }

    /**
     * Download model with progress
     */
    fun startDownload(modelId: String) {
        viewModelScope.launch {
            try {
                Log.d(TAG, "⬇️ Starting download for model: $modelId")

                _uiState.update {
                    it.copy(
                        selectedModelId = modelId,
                        isLoadingModel = true,
                        loadingProgress = "Starting download...",
                    )
                }

                // Call SDK download API - it returns a Flow<DownloadProgress>
                RunAnywhere.downloadModel(modelId)
                    .catch { e ->
                        Log.e(TAG, "❌ Download stream error: ${e.message}")
                        _uiState.update {
                            it.copy(
                                isLoadingModel = false,
                                selectedModelId = null,
                                loadingProgress = "",
                                error = e.message ?: "Download failed",
                            )
                        }
                    }
                    .collect { progress ->
                        val percent = (progress.progress * 100).toInt()
                        Log.d(TAG, "📥 Download progress: $percent%")
                        _uiState.update {
                            it.copy(loadingProgress = "Downloading... $percent%")
                        }
                    }

                Log.d(TAG, "✅ Download completed for $modelId")

                // Small delay to ensure registry update propagates
                delay(500)

                // Reload models after download completes
                loadModelsAndFrameworks()

                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        selectedModelId = null,
                        loadingProgress = "",
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Download failed for $modelId: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        selectedModelId = null,
                        loadingProgress = "",
                        error = e.message ?: "Download failed",
                    )
                }
            }
        }
    }

    /**
     * Select and load model - context-aware loading
     * Matches iOS context-based loading
     */
    suspend fun selectModel(modelId: String) {
        try {
            Log.d(TAG, "🔄 Loading model into memory: $modelId (context: $context)")

            _uiState.update {
                it.copy(
                    selectedModelId = modelId,
                    isLoadingModel = true,
                    loadingProgress = "Loading model into memory...",
                )
            }

            // Context-aware model loading - matches iOS exactly
            when (context) {
                ModelSelectionContext.LLM -> {
                    RunAnywhere.loadLLMModel(modelId)
                }
                ModelSelectionContext.STT -> {
                    RunAnywhere.loadSTTModel(modelId)
                }
                ModelSelectionContext.TTS -> {
                    RunAnywhere.loadTTSVoice(modelId)
                }
                ModelSelectionContext.VOICE -> {
                    // For voice context, determine from model category
                    val model = _uiState.value.models.find { it.id == modelId }
                    when (model?.category) {
                        ModelCategory.SPEECH_RECOGNITION -> RunAnywhere.loadSTTModel(modelId)
                        ModelCategory.SPEECH_SYNTHESIS -> RunAnywhere.loadTTSVoice(modelId)
                        else -> RunAnywhere.loadLLMModel(modelId)
                    }
                }
            }

            Log.d(TAG, "✅ Model loaded successfully: $modelId")

            // Get the loaded model
            val loadedModel = _uiState.value.models.find { it.id == modelId }

            _uiState.update {
                it.copy(
                    loadingProgress = "Model loaded successfully!",
                    isLoadingModel = false,
                    selectedModelId = null,
                    currentModel = loadedModel,
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to load model $modelId: ${e.message}", e)
            _uiState.update {
                it.copy(
                    isLoadingModel = false,
                    selectedModelId = null,
                    loadingProgress = "",
                    error = e.message ?: "Failed to load model",
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

    companion object {
        private const val TAG = "ModelSelectionVM"
    }
}

/**
 * UI State for Model Selection Bottom Sheet
 */
data class ModelSelectionUiState(
    val context: ModelSelectionContext = ModelSelectionContext.LLM,
    val deviceInfo: DeviceInfo? = null,
    val models: List<ModelInfo> = emptyList(),
    val frameworks: List<InferenceFramework> = emptyList(),
    val expandedFramework: InferenceFramework? = null,
    val selectedModelId: String? = null,
    val currentModel: ModelInfo? = null,
    val isLoading: Boolean = true,
    val isLoadingModel: Boolean = false,
    val loadingProgress: String = "",
    val error: String? = null,
)
