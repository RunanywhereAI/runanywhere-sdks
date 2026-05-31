package com.runanywhere.runanywhereai.presentation.models

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelEventKind
import ai.runanywhere.proto.v1.ModelListRequest
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.models.AppDeviceInfo
import com.runanywhere.runanywhereai.models.ModelSelectionContext
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.extensions.Models.displayName
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
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
            val deviceInfo =
                try {
                    AppDeviceInfo.current()
                } catch (_: Exception) {
                    null
                }
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

                // Call SDK to get available models via the proto-backed registry.
                // `listModels()` replaced the removed `availableModels()` helper.
                val allModels =
                    RunAnywhere
                        .listModels(ModelListRequest())
                        .models
                        ?.models
                        .orEmpty()
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
                if (context == ModelSelectionContext.TTS && !relevantFrameworks.contains(InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS)) {
                    relevantFrameworks.add(0, InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS)
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
    private suspend fun getCurrentLoadedModelIdForContext(): String? =
        when (context) {
            ModelSelectionContext.LLM ->
                RunAnywhere
                    .currentModel(CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_LANGUAGE))
                    .model_id
                    .takeIf { it.isNotEmpty() }
            ModelSelectionContext.STT ->
                RunAnywhere
                    .currentModel(CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION))
                    .model_id
                    .takeIf { it.isNotEmpty() }
            ModelSelectionContext.TTS ->
                RunAnywhere
                    .currentModel(CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS))
                    .model_id
                    .takeIf { it.isNotEmpty() }
            ModelSelectionContext.VAD ->
                RunAnywhere
                    .currentModel(CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION))
                    .model_id
                    .takeIf { it.isNotEmpty() }
            ModelSelectionContext.VOICE -> null
            ModelSelectionContext.RAG_EMBEDDING,
            ModelSelectionContext.RAG_LLM,
            -> null
            ModelSelectionContext.VLM ->
                RunAnywhere
                    .currentModel(CurrentModelRequest(category = ModelCategory.MODEL_CATEGORY_MULTIMODAL))
                    .model_id
                    .takeIf { it.isNotEmpty() }
        }

    private fun isModelRelevantForContext(
        category: ModelCategory,
        ctx: ModelSelectionContext,
    ): Boolean = ctx.isCategoryRelevant(category)

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
    fun getModelsForFramework(framework: InferenceFramework): List<RAModelInfo> =
        _uiState.value.models.filter { model ->
            model.framework == framework
        }

    /**
     * Download a model via the proto-canonical SDK API:
     *
     *  1. `CppBridgeDownload.start(DownloadStartRequest)` kicks off the C++ download.
     *  2. The SDK emits `MODEL_EVENT_KIND_DOWNLOAD_PROGRESS` / `_COMPLETED` events
     *     which our [subscribeToDownloadEvents] handler updates the UI from.
     *  3. On `DOWNLOAD_COMPLETED`, refresh the registry so the row flips to
     *     "Downloaded".
     *
     * Mirrors the iOS path which calls `RunAnywhere.downloadModel(...)`. Kotlin's
     * legacy `RunAnywhere.downloadModel(id)` convenience was deleted in B10; the
     * canonical replacement is the proto API exposed via `CppBridgeDownload`.
     */
    fun startDownload(modelId: String) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    selectedModelId = modelId,
                    isLoadingModel = true,
                    loadingProgress = "Starting download…",
                )
            }

            val model =
                try {
                    RunAnywhere
                        .listModels(
                            ai.runanywhere.proto.v1
                                .ModelListRequest(),
                        ).models
                        ?.models
                        ?.firstOrNull { it.id == modelId }
                } catch (_: Throwable) {
                    null
                }

            if (model == null) {
                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        selectedModelId = null,
                        loadingProgress = "",
                        error = "Model not in registry: $modelId",
                    )
                }
                return@launch
            }

            try {
                RunAnywhere.downloadModel(model) { progress ->
                    val pct =
                        if (progress.total_bytes > 0) {
                            (progress.bytes_downloaded.toDouble() / progress.total_bytes * 100).toInt()
                        } else {
                            ((progress.stage_progress).coerceIn(0f, 1f) * 100).toInt()
                        }
                    _uiState.update {
                        it.copy(loadingProgress = "Downloading… $pct%")
                    }
                }
                Timber.i("✅ Download complete for $modelId")
                loadModelsAndFrameworks()
                _uiState.update {
                    it.copy(
                        isLoadingModel = false,
                        selectedModelId = null,
                        loadingProgress = "",
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "❌ Download failed for $modelId")
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
            val loadCategory =
                when (context) {
                    ModelSelectionContext.LLM -> ModelCategory.MODEL_CATEGORY_LANGUAGE
                    ModelSelectionContext.STT -> ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
                    ModelSelectionContext.TTS -> ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
                    ModelSelectionContext.VAD -> ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
                    // The Android VLM catalog (ModelBootstrap.VLM_*) seeds entries with
                    // MODEL_CATEGORY_MULTIMODAL and the rest of the app — including
                    // currentModel(category = MULTIMODAL) and the Swift reference path —
                    // queries them under that category. Loading under VISION would record
                    // the loaded-model state in a category that no consumer reads from,
                    // leaving the picker convinced the just-loaded VLM is "not loaded".
                    ModelSelectionContext.VLM -> {
                        val model = _uiState.value.models.find { it.id == modelId }
                        model?.category ?: ModelCategory.MODEL_CATEGORY_MULTIMODAL
                    }
                    ModelSelectionContext.VOICE -> {
                        val model = _uiState.value.models.find { it.id == modelId }
                        when (model?.category) {
                            ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION ->
                                ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION
                            ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS ->
                                ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS
                            else -> ModelCategory.MODEL_CATEGORY_LANGUAGE
                        }
                    }
                    ModelSelectionContext.RAG_EMBEDDING,
                    ModelSelectionContext.RAG_LLM,
                    -> null
                }

            val selectedModel = _uiState.value.models.find { it.id == modelId }
            // Platform plugin is Apple-only; Android uses the example app's
            // TextToSpeech API for system-tts (mirrors iOS SystemTTSRow bypass).
            val skipCppLoad =
                loadCategory == null ||
                    modelId == "system-tts" ||
                    selectedModel?.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS

            if (skipCppLoad) {
                val reason =
                    when {
                        loadCategory == null -> "RAG context"
                        else -> "System TTS (platform API, no C++ backend on Android)"
                    }
                Timber.d("ℹ️ $reason: selecting model by reference only (no load): $modelId")
            } else {
                val result =
                    RunAnywhere.loadModel(
                        RAModelLoadRequest(model_id = modelId, category = loadCategory),
                    )
                if (!result.success) {
                    val errMsg = result.error_message.ifBlank { "unknown load error" }
                    Timber.e("❌ Model load FAILED for $modelId (category=$loadCategory): $errMsg")
                    throw com.runanywhere.sdk.foundation.errors.SDKException.model(
                        "Model load failed: $errMsg",
                    )
                }
                Timber.i("✅ Model load succeeded for $modelId (category=$loadCategory)")
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
    class Factory(
        private val context: ModelSelectionContext,
    ) : ViewModelProvider.Factory {
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
    val deviceInfo: AppDeviceInfo? = null,
    val models: List<RAModelInfo> = emptyList(),
    val frameworks: List<InferenceFramework> = emptyList(),
    val expandedFramework: InferenceFramework? = null,
    val selectedModelId: String? = null,
    val currentModel: RAModelInfo? = null,
    val isLoading: Boolean = true,
    val isLoadingModel: Boolean = false,
    val loadingProgress: String = "",
    val error: String? = null,
)
