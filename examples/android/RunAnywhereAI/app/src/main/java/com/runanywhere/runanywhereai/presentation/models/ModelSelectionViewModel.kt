package com.runanywhere.runanywhereai.presentation.models

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import ai.runanywhere.proto.v1.ModelEventKind
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
// Round 3 KOTLIN: currentLLMModel is now a sync val property.
import com.runanywhere.sdk.public.extensions.currentLLMModel
import com.runanywhere.sdk.public.extensions.currentSTTModelId
import com.runanywhere.sdk.public.extensions.currentTTSVoiceId
import com.runanywhere.sdk.public.extensions.currentVLMModelId
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.loadSTTModel
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import com.runanywhere.sdk.public.extensions.loadVLMModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber

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
            Timber.d("📡 Subscribed to download progress events")
            EventBus.events
                .mapNotNull { it.model }
                .collect { event ->
                    when (event.kind) {
                        ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_PROGRESS -> {
                            val progressPercent = (event.progress * 100).toInt()
                            Timber.d("📊 Download progress: ${event.model_id} - $progressPercent%")
                            _uiState.update {
                                it.copy(loadingProgress = "Downloading... $progressPercent%")
                            }
                        }
                        ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_COMPLETED -> {
                            Timber.d("✅ Download completed: ${event.model_id}")
                            loadModelsAndFrameworks() // Refresh models list
                        }
                        ModelEventKind.MODEL_EVENT_KIND_DOWNLOAD_FAILED -> {
                            Timber.e("❌ Download failed: ${event.model_id} - ${event.error}")
                            _uiState.update {
                                it.copy(
                                    isLoadingModel = false,
                                    loadingProgress = "",
                                    error = event.error.ifBlank { "Download failed" },
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
                Timber.d("🔄 Loading models and frameworks for context: $context")

                // Call SDK to get available models
                val allModels = RunAnywhere.availableModels()
                Timber.d("📦 Fetched ${allModels.size} total models from SDK")

                // Filter models by context - matches iOS relevantCategories filtering
                val filteredModels =
                    allModels.filter { model ->
                        isModelRelevantForContext(model.category, context)
                    }
                Timber.d("📦 Filtered to ${filteredModels.size} models for context $context")

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
                    Timber.d("📱 Added System TTS for TTS context")
                }

                Timber.d("✅ Loaded ${filteredModels.size} models and ${relevantFrameworks.size} frameworks")
                relevantFrameworks.forEach { fw ->
                    Timber.d("   Framework: ${fw.displayName}")
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
                    Timber.d("✅ Found currently loaded model for context $context: ${currentLoadedModel.id}")
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
                Timber.e(e, "❌ Failed to load models: ${e.message}")
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
     *
     * RAG contexts (RAG_EMBEDDING, RAG_LLM) return null — RAG models are selected
     * by file path at pipeline creation time and are not pre-loaded into memory.
     * This mirrors iOS behavior where ragEmbedding/ragLLM contexts skip the model loader.
     */
    private suspend fun getCurrentLoadedModelIdForContext(): String? {
        return when (context) {
            // Round 3 KOTLIN: currentLLMModel is now a sync val property.
            ModelSelectionContext.LLM -> RunAnywhere.currentLLMModel?.id
            ModelSelectionContext.STT -> RunAnywhere.currentSTTModelId
            ModelSelectionContext.TTS -> RunAnywhere.currentTTSVoiceId
            ModelSelectionContext.VOICE -> null
            ModelSelectionContext.RAG_EMBEDDING,
            ModelSelectionContext.RAG_LLM,
            -> null
            ModelSelectionContext.VLM -> RunAnywhere.currentVLMModelId
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
            ModelSelectionContext.RAG_EMBEDDING ->
                category == ModelCategory.EMBEDDING
            ModelSelectionContext.RAG_LLM ->
                category == ModelCategory.LANGUAGE
            ModelSelectionContext.VLM ->
                category == ModelCategory.MULTIMODAL ||
                    category == ModelCategory.VISION
        }
    }

    /**
     * Toggle framework expansion
     */
    fun toggleFramework(framework: InferenceFramework) {
        Timber.d("🔀 Toggling framework: ${framework.displayName}")
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
                Timber.d("⬇️ Starting download for model: $modelId")

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
                        Timber.e("❌ Download stream error: ${e.message}")
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
                        val percent = (progress.stage_progress * 100).toInt()
                        Timber.d("📥 Download progress: $percent%")
                        _uiState.update {
                            it.copy(loadingProgress = "Downloading... $percent%")
                        }
                    }

                Timber.d("✅ Download completed for $modelId")

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
                Timber.e(e, "❌ Download failed for $modelId: ${e.message}")
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
     *
     * For RAG contexts (RAG_EMBEDDING, RAG_LLM), the model is selected but NOT loaded into
     * memory — RAG models are referenced by file path at pipeline creation time.
     * This matches iOS behavior where ragEmbedding/ragLLM contexts skip the model loader.
     */
    suspend fun selectModel(modelId: String) {
        try {
            Timber.d("🔄 Loading model into memory: $modelId (context: $context)")

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
                    val model = _uiState.value.models.find { it.id == modelId }
                    when (model?.category) {
                        ModelCategory.SPEECH_RECOGNITION -> RunAnywhere.loadSTTModel(modelId)
                        ModelCategory.SPEECH_SYNTHESIS -> RunAnywhere.loadTTSVoice(modelId)
                        else -> RunAnywhere.loadLLMModel(modelId)
                    }
                }
                ModelSelectionContext.RAG_EMBEDDING,
                ModelSelectionContext.RAG_LLM,
                -> {
                    // RAG models are referenced by file path only
                    Timber.d("ℹ️ RAG context: selecting model by reference only (no load): $modelId")
                }
                ModelSelectionContext.VLM -> {
                    RunAnywhere.loadVLMModel(modelId)
                }
            }

            Timber.d("✅ Model selected successfully: $modelId")

            // Get the loaded model
            val loadedModel = _uiState.value.models.find { it.id == modelId }

            _uiState.update {
                it.copy(
                    loadingProgress = "Model selected!",
                    isLoadingModel = false,
                    selectedModelId = null,
                    currentModel = loadedModel,
                )
            }
        } catch (e: Exception) {
            Timber.e(e, "❌ Failed to load model $modelId: ${e.message}")
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

    companion object
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
