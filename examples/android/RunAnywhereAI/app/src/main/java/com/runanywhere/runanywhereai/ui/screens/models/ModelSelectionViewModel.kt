package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.ModelListRequest
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.BackendAvailability
import com.runanywhere.runanywhereai.data.ModelBootstrap
import com.runanywhere.runanywhereai.data.isVisibleForNativeNpuCatalog
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.download.ModelDownloadService
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
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.takeWhile
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

    // In-flight collector for a user-initiated download. Cancelling this cancels
    // the SDK stream, whose finally block hands off to the native cancel while
    // preserving resume bytes. Tracks both the foreground-service observation and
    // the in-VM fallback path so [cancelDownload] works in either case.
    private var downloadJob: Job? = null

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
            // Probe device-dependent backends (QHexRT) before the first list so
            // unavailable-backend rows are filtered from the very first render.
            BackendAvailability.refresh()
            ModelBootstrap.npuCatalogSnapshots.collect { snapshot ->
                reload(snapshot.registeredModelIds)
            }
        }
        viewModelScope.launch {
            // Re-filter live when backend availability changes (e.g. the async
            // NPU probe resolves, or bootstrap reports a registration outcome).
            // Gate on bootstrap so we never call listModels before SDK init.
            GlobalState.awaitBootstrapComplete()
            BackendAvailability.snapshots.collect { reload() }
        }
    }

    fun refresh() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload(
        registeredNpuIds: Set<String> = ModelBootstrap.registeredNpuModelIds,
    ) {
        try {
            // Union live QHexRT registration with what is already downloaded so an
            // on-disk NPU bundle stays selectable even when re-registration is
            // skipped offline (see isVisibleForNativeNpuCatalog).
            val models = RunAnywhere.listModels(ModelListRequest()).models?.models.orEmpty()
                .filter { context.accepts(it) }
                // Native QHexRT registration is the source of truth. This also
                // hides stale rows left by older app versions that registered
                // HNPU definitions through the generic URL path.
                .filter { it.isVisibleForNativeNpuCatalog(registeredNpuIds) }
                // Hide rows whose backend is not packaged/available on this build
                // + device (e.g. Sherpa voice on an NPU-only slice); otherwise
                // they look tappable and then hard-fail at load.
                .filter { BackendAvailability.isAvailable(it.framework) }
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

    // User-initiated download. Prefers the foreground service so the transfer
    // survives the screen turning off (Doze). Falls back to an in-VM download
    // when the service can't be started (e.g. app in background). Either path is
    // cancellable via [cancelDownload].
    fun download(model: RAModelInfo) {
        if (isReady(model)) return
        if (model.requiresHfAuth() && SettingsRepository.settings.hfToken.isBlank()) {
            state = state.copy(
                error = "Add a Hugging Face token in Settings to download private HNPU/QHexRT models.",
            )
            return
        }
        // Replace any prior collector/fallback so only one download is tracked.
        downloadJob?.cancel()
        if (ModelDownloadService.start(model)) {
            observeForegroundDownload(model)
        } else {
            downloadJob = viewModelScope.launch { downloadInternal(model) }
        }
    }

    // Mirrors the foreground service's progress/terminal state into this VM's row
    // state so the picker shows the same bar the notification does. The collector
    // job is the cancellation handle for the foreground path.
    private fun observeForegroundDownload(model: RAModelInfo) {
        downloadJob = viewModelScope.launch { collectForegroundDownload(model) }
    }

    // Mirrors the foreground service's progress/terminal state into this VM's row and
    // completes when THIS model reaches a terminal status — OR when the service is
    // preempted by a different download — so the collector can never hang on a stale
    // or other-model snapshot. Shared by the fire-and-forget picker path and the
    // awaiting prepare() path.
    private suspend fun collectForegroundDownload(model: RAModelInfo) {
        state = state.copy(busyModelId = model.id, progressPercent = 0, error = null)
        var sawOurModel = false
        ModelDownloadService.state
            .takeWhile { snapshot ->
                when {
                    snapshot == null -> true // service hasn't reported yet
                    snapshot.modelId == model.id -> {
                        sawOurModel = true
                        snapshot.status == ModelDownloadService.Status.RUNNING
                    }
                    // A different model is active: keep waiting only during our
                    // pre-registration window. Once we've tracked our model, a switch
                    // means we were preempted — stop so applyTerminalDownload clears us.
                    else -> !sawOurModel
                }
            }
            .collect { snapshot ->
                if (snapshot?.modelId == model.id &&
                    snapshot.status == ModelDownloadService.Status.RUNNING
                ) {
                    state = state.copy(busyModelId = model.id, progressPercent = snapshot.progressPercent)
                }
            }
        // The flow completed on a terminal (or preemption) snapshot; apply + clean up.
        applyTerminalDownload(model, ModelDownloadService.state.value)
    }

    private suspend fun applyTerminalDownload(
        model: RAModelInfo,
        snapshot: ModelDownloadService.Download?,
    ) {
        if (snapshot == null || snapshot.modelId != model.id) {
            state = state.copy(busyModelId = null, progressPercent = null)
            return
        }
        when (snapshot.status) {
            ModelDownloadService.Status.COMPLETED -> {
                state = state.copy(busyModelId = null, progressPercent = null)
                reload()
            }
            ModelDownloadService.Status.FAILED ->
                state = state.copy(
                    busyModelId = null,
                    progressPercent = null,
                    error = snapshot.error ?: "Download failed",
                )
            else ->
                state = state.copy(busyModelId = null, progressPercent = null)
        }
        ModelDownloadService.clearIfTerminal(model.id)
    }

    // Cancels the in-flight download for [modelId]. Cancels the foreground-service
    // job (which the SDK unwinds, preserving resume bytes) and the local collector.
    fun cancelDownload(modelId: String) {
        viewModelScope.launch {
            ModelDownloadService.cancel(modelId)
            downloadJob?.cancel()
            downloadJob = null
            if (state.busyModelId == modelId) {
                state = state.copy(busyModelId = null, progressPercent = null)
            }
        }
    }

    // Downloads the model (respecting the HF-token gate) with progress on this VM's
    // state. Returns true when the model is on disk afterwards. Shared by the in-VM
    // download fallback and [prepare].
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
        if (!awaitDownload(model)) return false
        val onDisk = state.models.firstOrNull { it.id == model.id } ?: model
        return select(onDisk)
    }

    // Downloads via the foreground service (survives screen-off / Doze) and suspends
    // until this model reaches a terminal state, falling back to the in-VM stream when
    // the service can't start (e.g. app already backgrounded). Returns true when the
    // model is on disk afterward. Used by prepare() so voice-pipeline staging gets the
    // same wake-lock/foreground guarantees as user-initiated picker downloads.
    private suspend fun awaitDownload(model: RAModelInfo): Boolean {
        if (isReady(model)) return true
        if (model.requiresHfAuth() && SettingsRepository.settings.hfToken.isBlank()) {
            state = state.copy(
                error = "Add a Hugging Face token in Settings to download private HNPU/QHexRT models.",
            )
            return false
        }
        if (!ModelDownloadService.start(model)) return downloadInternal(model)
        collectForegroundDownload(model)
        return isReady(model)
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
