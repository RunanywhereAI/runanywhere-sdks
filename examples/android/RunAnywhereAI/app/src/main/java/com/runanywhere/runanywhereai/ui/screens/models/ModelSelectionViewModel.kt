package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.CurrentModelRequest
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelListRequest
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.extensions.currentModel
import com.runanywhere.sdk.public.extensions.downloadModelStream
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

data class ModelSelectionState(
    val models: List<RAModelInfo> = emptyList(),
    val currentModelId: String? = null,
    val busyModelId: String? = null,
    val progressPercent: Int? = null,
    val isLoading: Boolean = true,
    val error: String? = null,
)

class ModelSelectionViewModel(
    private val context: ModelSelectionContext,
) : ViewModel() {

    var state by mutableStateOf(ModelSelectionState())
        private set

    val title: String get() = context.title

    private val isLlm: Boolean get() = context == ModelSelectionContext.LLM

    init {
        viewModelScope.launch {
            while (!GlobalState.ready) delay(150)
            reload()
        }
    }

    fun refresh() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        try {
            val models = RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
                .filter { context.accepts(it.category) }
                .filter { context.allowsBuiltIn || !isBuiltIn(it) }
            state = state.copy(models = models, isLoading = false, error = null)
            syncCurrent(models)
            autoLoadIfNeeded(models)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("model list failed", e)
            state = state.copy(isLoading = false, error = e.message ?: "Failed to load models")
        }
    }

    fun download(model: RAModelInfo) {
        viewModelScope.launch {
            state = state.copy(busyModelId = model.id, progressPercent = 0, error = null)
            try {
                RunAnywhere.downloadModelStream(model).collect { p ->
                    val pct = if (p.total_bytes > 0) {
                        (p.bytes_downloaded * 100 / p.total_bytes).toInt()
                    } else {
                        (p.stage_progress.coerceIn(0f, 1f) * 100).toInt()
                    }
                    state = state.copy(progressPercent = pct)
                }
                state = state.copy(busyModelId = null, progressPercent = null)
                reload()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("download failed: ${model.id}", e)
                state = state.copy(busyModelId = null, progressPercent = null, error = e.message ?: "Download failed")
            }
        }
    }

    // Loads the model into memory and marks it current. Returns true on success so the caller
    // can dismiss. Built-in frameworks and RAG are selected by reference (no load).
    suspend fun select(model: RAModelInfo): Boolean {
        state = state.copy(busyModelId = model.id, error = null)
        return try {
            if (isBuiltIn(model) || context.loadCategory == null) {
                if (isLlm) GlobalState.model.set(model)
                state = state.copy(currentModelId = model.id, busyModelId = null)
                true
            } else {
                val result = RunAnywhere.loadModel(
                    RAModelLoadRequest(model_id = model.id, category = context.loadCategory),
                )
                if (result.success) {
                    if (isLlm) {
                        GlobalState.model.set(model)
                        GlobalState.lora.set(null)
                    }
                    state = state.copy(currentModelId = model.id, busyModelId = null)
                    true
                } else {
                    state = state.copy(busyModelId = null, error = result.error_message.ifBlank { "Load failed" })
                    false
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("load failed: ${model.id}", e)
            state = state.copy(busyModelId = null, error = e.message ?: "Load failed")
            false
        }
    }

    fun clearError() {
        state = state.copy(error = null)
    }

    fun isReady(model: RAModelInfo): Boolean = isBuiltIn(model) || model.isDownloadedOnDisk

    private suspend fun syncCurrent(models: List<RAModelInfo>) {
        val category = context.loadCategory ?: return
        val loadedId = runCatching {
            RunAnywhere.currentModel(CurrentModelRequest(category = category)).model_id.takeIf { it.isNotEmpty() }
        }.getOrNull() ?: return
        state = state.copy(currentModelId = loadedId)
        if (isLlm) models.firstOrNull { it.id == loadedId }?.let { GlobalState.model.set(it) }
    }

    private suspend fun autoLoadIfNeeded(models: List<RAModelInfo>) {
        if (!isLlm || GlobalState.model.isLoaded) return
        val category = context.loadCategory ?: return
        val candidate = models.firstOrNull { isReady(it) && !isBuiltIn(it) } ?: return
        // Several LLM-context view-models (scaffold + voice screen) reload
        // concurrently at startup; without this gate each one auto-loads the
        // same model in parallel.
        if (!autoLoadInFlight.compareAndSet(false, true)) return
        try {
            if (GlobalState.model.isLoaded) return
            runCatching {
                val result = RunAnywhere.loadModel(RAModelLoadRequest(model_id = candidate.id, category = category))
                if (result.success) {
                    GlobalState.model.set(candidate)
                    GlobalState.lora.set(null)
                }
            }.onFailure { RACLog.w("auto-load skipped: ${candidate.id}") }
        } finally {
            autoLoadInFlight.set(false)
        }
    }

    private fun isBuiltIn(model: RAModelInfo): Boolean =
        model.framework == InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS ||
            model.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS

    class Factory(private val context: ModelSelectionContext) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            ModelSelectionViewModel(context) as T
    }

    private companion object {
        val autoLoadInFlight = java.util.concurrent.atomic.AtomicBoolean(false)
    }
}
