package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.ModelListRequest
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.ModelBootstrap
import com.runanywhere.runanywhereai.data.isVisibleForNativeNpuCatalog
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.isBuiltIn
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.downloadModelStream
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.types.RAModelInfo
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

    // Which modality this picker is scoped to — used to highlight the per-modality
    // recommended model and to orchestrate the Voice AI pipeline.
    val modality: ModelSelectionContext get() = context

    private val isLlm: Boolean get() = context == ModelSelectionContext.LLM

    init {
        viewModelScope.launch {
            RuntimeModelSelection.observe(context).collect { snapshot ->
                state = state.copy(currentModelId = snapshot?.id)
            }
        }
        viewModelScope.launch {
            // SDK Phase 1 completes before ModelBootstrap finishes seeding the
            // registry. Suspend on the explicit bootstrap-complete signal, then
            // observe every catalog revision. The VM is activity-scoped, so a
            // one-shot load would stay stale after Settings applies an HF token.
            GlobalState.awaitBootstrapComplete()
            ModelBootstrap.npuCatalogSnapshots.collect { snapshot ->
                reload(snapshot.registeredModelIds)
            }
        }
    }

    fun refresh() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload(
        registeredNpuIds: Set<String> = ModelBootstrap.registeredNpuModelIds,
    ) {
        try {
            val models = RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
                .filter { context.accepts(it) }
                // Native QHexRT registration is the source of truth. This also
                // hides stale rows left by older app versions that registered
                // HNPU definitions through the generic URL path.
                .filter { it.isVisibleForNativeNpuCatalog(registeredNpuIds) }
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
        viewModelScope.launch { downloadInternal(model) }
    }

    // Downloads the model (respecting the HF-token gate) with progress on this VM's
    // state. Returns true when the model is on disk afterwards. Shared by [download]
    // and [prepare].
    private suspend fun downloadInternal(model: RAModelInfo): Boolean {
        if (isReady(model)) return true
        if (model.requiresHfAuth() && SettingsRepository.settings.hfToken.isBlank()) {
            state = state.copy(
                error = "Add a Hugging Face token in Settings to download private HNPU/QHexRT models.",
            )
            return false
        }
        state = state.copy(busyModelId = model.id, progressPercent = 0, error = null)
        return try {
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
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("download failed: ${model.id}", e)
            state = state.copy(busyModelId = null, progressPercent = null, error = e.message ?: "Download failed")
            false
        }
    }

    // One-shot "make this model usable": download if needed, then load + mark current.
    // Used by the Voice AI card to stage a whole pipeline component with one call.
    suspend fun prepare(model: RAModelInfo): Boolean {
        if (!downloadInternal(model)) return false
        val onDisk = state.models.firstOrNull { it.id == model.id } ?: model
        return select(onDisk)
    }

    fun delete(model: RAModelInfo) {
        viewModelScope.launch {
            state = state.copy(busyModelId = model.id, progressPercent = null, error = null)
            try {
                if (isLlm) LlmModelChangeInterlock.awaitReadyForModelChange()
                RunAnywhere.deleteModel(model.id)
                RuntimeModelSelection.clearModelEverywhere(model.id)
                reload()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("delete failed: ${model.id}", e)
                state = state.copy(error = e.message ?: "Delete failed")
            } finally {
                state = state.copy(busyModelId = null, progressPercent = null)
            }
        }
    }

    // Loads the model into memory and marks it current. Returns true on success so the caller
    // can dismiss. Only RAG references bypass lifecycle loading; platform built-ins such as
    // System TTS still create a native lifecycle service and must be loaded normally.
    suspend fun select(model: RAModelInfo): Boolean {
        state = state.copy(busyModelId = model.id, error = null)
        return try {
            if (!context.loadsModel) {
                RuntimeModelSelection.selectReference(context, model)
                state = state.copy(currentModelId = model.id, busyModelId = null)
                true
            } else {
                if (isLlm) {
                    // Loading a different LLM mutates process-wide native state.
                    // Let the activity-scoped chat revoke and fully cancel any
                    // request that still owns the old model before doing so.
                    LlmModelChangeInterlock.awaitReadyForModelChange()
                }
                val result = RunAnywhere.loadModel(model)
                if (result.success) {
                    val actual = RuntimeModelSelection.queryCurrent(context, state.models + model)
                    if (actual?.id != model.id) {
                        state = state.copy(
                            busyModelId = null,
                            error = "The runtime loaded ${actual?.id ?: "no model"} instead of ${model.id}.",
                        )
                        false
                    } else {
                        if (isLlm) GlobalState.lora.set(null)
                        state = state.copy(currentModelId = actual.id, busyModelId = null)
                        true
                    }
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

    fun isReady(model: RAModelInfo): Boolean = model.isBuiltIn || model.isDownloadedOnDisk

    fun isDeletable(model: RAModelInfo): Boolean = !model.isBuiltIn && model.isDownloadedOnDisk

    private suspend fun syncCurrent(models: List<RAModelInfo>) {
        if (!context.loadsModel) {
            state = state.copy(currentModelId = RuntimeModelSelection.cached(context)?.id)
            return
        }
        val loadedId = RuntimeModelSelection.queryCurrent(context, models)?.id
        state = state.copy(currentModelId = loadedId)
    }

    private suspend fun autoLoadIfNeeded(models: List<RAModelInfo>) {
        if (!isLlm || GlobalState.model.isLoaded) return
        val candidate = models.firstOrNull { isReady(it) && !it.isBuiltIn } ?: return
        runCatching {
            val result = RunAnywhere.loadModel(candidate)
            if (result.success) {
                RuntimeModelSelection.queryCurrent(context, models)
                GlobalState.lora.set(null)
            }
        }.onFailure { RACLog.w("auto-load skipped: ${candidate.id}") }
    }

    class Factory(private val context: ModelSelectionContext) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            ModelSelectionViewModel(context) as T
    }
}
