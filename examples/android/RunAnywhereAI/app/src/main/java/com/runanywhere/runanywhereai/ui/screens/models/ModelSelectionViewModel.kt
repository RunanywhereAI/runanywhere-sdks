package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.BackendAvailability
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.download.DownloadInterruptionState
import com.runanywhere.runanywhereai.download.DownloadProgressInfo
import com.runanywhere.runanywhereai.download.DownloadUpdate
import com.runanywhere.runanywhereai.download.ModelDownloadService
import com.runanywhere.runanywhereai.download.asState
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.isBuiltIn
import com.runanywhere.sdk.public.extensions.Models.isDownloadedOnDisk
import com.runanywhere.sdk.public.api.models
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

data class ModelSelectionState(
    val models: List<RAModelInfo> = emptyList(),
    val currentModelId: String? = null,
    // Loading, deleting — work this picker is doing itself. A download's busy row comes from
    // [downloadingModelId] instead, because the transfer outlives this ViewModel.
    val localBusyModelId: String? = null,
    // The model the foreground service is transferring right now, when this picker lists it.
    val downloadingModelId: String? = null,
    // Full transfer detail (rate, remaining, retry count), not just a percentage, so a row can
    // explain a slow download instead of only claiming a number.
    val downloadProgress: DownloadProgressInfo? = null,
    // Downloads that stopped with bytes still on disk, mirrored from the service so a row can
    // offer to continue one that started before this picker was opened.
    val interruptions: Map<String, ModelDownloadService.Interrupted> = emptyMap(),
    val isLoading: Boolean = true,
    val error: String? = null,
) {
    /** The one busy row, whichever kind of work is holding it. */
    val busyModelId: String? get() = downloadingModelId ?: localBusyModelId

    /**
     * The stopped transfer for [modelId], or null when there is nothing on disk to continue.
     * Handed to the row already interpreted, so the note and the trailing verb are read from one
     * value and cannot disagree about what happened — and no list layout has to know what a
     * download-service record means.
     */
    fun interruptionFor(modelId: String): DownloadInterruptionState? = interruptions[modelId]?.asState()
}

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

    // In-flight collector for the in-VM fallback download — the path taken only when the
    // foreground service cannot be started. Service-owned downloads are watched through
    // [ModelDownloadService.active] and have no job here to cancel.
    private var downloadJob: Job? = null

    init {
        viewModelScope.launch {
            RuntimeModelSelection.observe(context).collect { snapshot ->
                state = state.copy(currentModelId = snapshot?.id)
            }
        }
        viewModelScope.launch {
            // Wait until SDK initialization and the regular app catalog seed are complete.
            GlobalState.awaitBootstrapComplete()
            // Probe device-dependent backends (QHexRT) before the first list so
            // unavailable-backend rows are filtered from the very first render.
            BackendAvailability.refresh()
            reload()
        }
        viewModelScope.launch {
            // Re-filter live when backend availability changes (e.g. the async
            // NPU probe resolves, or bootstrap reports a registration outcome).
            // Gate on bootstrap so we never call listModels before SDK init.
            GlobalState.awaitBootstrapComplete()
            BackendAvailability.snapshots.collect { reload() }
        }
        viewModelScope.launch {
            // The single source of "is something downloading". A transfer started before this
            // ViewModel existed — the app was backgrounded and the Activity recreated, or the
            // picker was simply closed and reopened — shows up here with no adoption dance, and a
            // transfer that ends while the picker is closed cannot strand a row mid-progress.
            ModelDownloadService.active.collect { snapshot ->
                val previous = state.downloadingModelId
                syncDownloadState(snapshot)
                // A transfer this picker was showing just ended. Re-read the catalog so the row
                // reports what is genuinely on disk rather than what the last frame claimed.
                if (previous != null && snapshot?.modelId != previous) reload()
            }
        }
        viewModelScope.launch {
            ModelDownloadService.interrupted.collect { records ->
                state = state.copy(interruptions = records)
            }
        }
    }

    /** Mirror the service's live transfer into this picker's row state, if it lists that model. */
    private fun syncDownloadState(snapshot: ModelDownloadService.Active? = ModelDownloadService.active.value) {
        val mine = snapshot?.takeIf { active -> state.models.any { it.id == active.modelId } }
        state = state.copy(
            downloadingModelId = mine?.modelId,
            downloadProgress = mine?.progress,
        )
    }

    fun refresh() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        try {
            val models = RunAnywhere.models.list()
                .filter { context.accepts(it) }
                // Hide rows whose backend is not packaged/available on this build
                // + device (e.g. Sherpa voice on an NPU-only slice); otherwise
                // they look tappable and then hard-fail at load.
                .filter { BackendAvailability.isAvailable(it.framework) }
            state = state.copy(models = models, isLoading = false, error = null)
            // A model that is on disk has nothing left to resume, so an offer to continue it would
            // be describing bytes that are now a finished file.
            ModelDownloadService.interrupted.value.keys
                .filter { id -> models.any { it.id == id && isReady(it) } }
                .forEach { ModelDownloadService.forget(it) }
            // The service's flow is conflated, so a transfer that was already running when this
            // picker was built emitted before [models] existed to match it against. Re-check now.
            syncDownloadState()
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
    // survives the app being backgrounded and the screen turning off (Doze). Falls
    // back to an in-VM download when the service can't be started (e.g. app already
    // in the background). Either path is cancellable via [cancelDownload].
    fun download(model: RAModelInfo) {
        if (isReady(model)) return
        if (!hasTokenForDownload(model)) return
        // Replace any prior in-VM fallback so only one download is tracked here.
        downloadJob?.cancel()
        if (ModelDownloadService.start(model)) {
            // Paint the busy row on this frame rather than waiting for the service's flow to
            // schedule; the same snapshot arrives from the collector a moment later.
            state = state.copy(
                downloadingModelId = model.id,
                downloadProgress = DownloadProgressInfo(),
                error = null,
            )
        } else {
            downloadJob = viewModelScope.launch { downloadInternal(model) }
        }
    }

    // Cancels the in-flight download for [modelId]. The service unwinds the SDK stream, which
    // preserves resume bytes and publishes the paused record every picker reads.
    fun cancelDownload(modelId: String) {
        viewModelScope.launch {
            ModelDownloadService.cancel(modelId)
            downloadJob?.cancel()
            downloadJob = null
        }
    }

    // The HF-token gate, shared by every download entry point. Returns false (with the row's error
    // set) when a private model is asked for without a token to fetch it.
    private fun hasTokenForDownload(model: RAModelInfo): Boolean {
        if (!model.requiresHfAuth() || SettingsRepository.settings.hfToken.isNotBlank()) return true
        state = state.copy(
            error = "Add a Hugging Face token in Settings to download private HNPU/QHexRT models.",
        )
        return false
    }

    // Downloads the model on this ViewModel's own scope. Only used when the foreground service
    // could not be started — it has no wake lock and dies with the process, so it is a fallback,
    // not a peer. Returns true when the model is on disk afterwards.
    private suspend fun downloadInternal(model: RAModelInfo): Boolean {
        if (isReady(model)) return true
        if (!hasTokenForDownload(model)) return false
        state = state.copy(
            downloadingModelId = model.id,
            downloadProgress = DownloadProgressInfo(),
            error = null,
        )
        ModelDownloadService.forget(model.id)
        var latest = DownloadProgressInfo()
        return try {
            // Same as ModelDownloadService: free resident weights so the RAM
            // preflight can pass when another STT/LLM is still loaded.
            RuntimeModelSelection.unloadAllForDownload()
            var finished = false
            RunAnywhere.models.download(model.id).collect { event ->
                when (val update = DownloadProgressInfo.advance(latest, event)) {
                    is DownloadUpdate.Advanced -> {
                        latest = update.info
                        state = state.copy(downloadProgress = update.info)
                    }
                    DownloadUpdate.Finished -> finished = true
                    // The SDK reports a failure as a terminal event and then ends the stream
                    // normally, so the end of the stream is not on its own a success.
                    is DownloadUpdate.Stopped -> ModelDownloadService.noteInterrupted(
                        modelId = model.id,
                        cancelled = update.cancelled,
                        message = update.message,
                        progress = latest.takeIf { it.bytesDone > 0 },
                    )
                    DownloadUpdate.Ignored -> Unit
                }
            }
            state = state.copy(downloadingModelId = null, downloadProgress = null)
            reload()
            finished && isReady(model)
        } catch (e: CancellationException) {
            ModelDownloadService.noteInterrupted(
                modelId = model.id,
                cancelled = true,
                progress = latest.takeIf { it.bytesDone > 0 },
            )
            state = state.copy(downloadingModelId = null, downloadProgress = null)
            throw e
        } catch (e: Exception) {
            RACLog.e("download failed: ${model.id}", e)
            ModelDownloadService.noteInterrupted(
                modelId = model.id,
                cancelled = false,
                message = e.message ?: "Download failed",
                progress = latest.takeIf { it.bytesDone > 0 },
            )
            state = state.copy(downloadingModelId = null, downloadProgress = null)
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

    // Download-only staging step. Multi-component flows (Voice AI) fetch every
    // missing model first because each download unloads resident models for RAM
    // headroom — loading between downloads would be undone by the next one.
    suspend fun ensureDownloaded(model: RAModelInfo): Boolean = awaitDownload(model)

    // Downloads via the foreground service (survives backgrounding / screen-off) and suspends until
    // this model is no longer the running transfer, falling back to the in-VM stream when the
    // service can't start. Returns true when the model is on disk afterward, so voice-pipeline
    // staging gets the same wake-lock/foreground guarantees as user-initiated picker downloads.
    private suspend fun awaitDownload(model: RAModelInfo): Boolean {
        if (isReady(model)) return true
        if (!hasTokenForDownload(model)) return false
        if (!ModelDownloadService.start(model)) return downloadInternal(model)
        ModelDownloadService.awaitFinish(model.id)
        // The catalog carries the on-disk path, so it has to be re-read before "is it ready?"
        // can be answered from anything better than the last progress frame.
        reload()
        return isReady(model)
    }

    fun delete(model: RAModelInfo) {
        viewModelScope.launch {
            state = state.copy(localBusyModelId = model.id, error = null)
            try {
                if (isLlm) LlmModelChangeInterlock.awaitReadyForModelChange()
                RunAnywhere.models.delete(model.id)
                RuntimeModelSelection.clearModelEverywhere(model.id)
                // Its partial bytes went with it, so there is nothing left to resume.
                ModelDownloadService.forget(model.id)
                reload()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("delete failed: ${model.id}", e)
                state = state.copy(error = e.message ?: "Delete failed")
            } finally {
                state = state.copy(localBusyModelId = null)
            }
        }
    }

    // Loads the model into memory and marks it current. Returns true on success so the caller
    // can dismiss. Only RAG references bypass lifecycle loading; platform built-ins such as
    // System TTS still create a native lifecycle service and must be loaded normally.
    suspend fun select(model: RAModelInfo): Boolean {
        state = state.copy(localBusyModelId = model.id, error = null)
        return try {
            if (!context.loadsModel) {
                RuntimeModelSelection.selectReference(context, model)
                state = state.copy(currentModelId = model.id, localBusyModelId = null)
                true
            } else {
                if (isLlm) {
                    // Loading a different LLM mutates process-wide native state.
                    // Let the activity-scoped chat revoke and fully cancel any
                    // request that still owns the old model before doing so.
                    LlmModelChangeInterlock.awaitReadyForModelChange()
                }
                RunAnywhere.models.load(model.id)
                val actual = RuntimeModelSelection.queryCurrent(context, state.models + model)
                if (actual?.id != model.id) {
                    state = state.copy(
                        localBusyModelId = null,
                        error = "The runtime loaded ${actual?.id ?: "no model"} instead of ${model.id}.",
                    )
                    false
                } else {
                    if (isLlm) GlobalState.lora.set(null)
                    state = state.copy(currentModelId = actual.id, localBusyModelId = null)
                    true
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("load failed: ${model.id}", e)
            state = state.copy(localBusyModelId = null, error = e.message ?: "Load failed")
            false
        }
    }

    fun clearError() {
        state = state.copy(error = null)
    }

    fun isReady(model: RAModelInfo): Boolean = model.isBuiltIn || model.isDownloadedOnDisk

    // Loaded-into-the-lifecycle readiness (currentModelId is set only on a successful select()/load).
    // Distinct from isReady() which is merely "downloaded on disk" — the voice mic gate needs LOADED,
    // so the setup card must reflect the same thing or it shows a green "Ready" over a dead mic.
    fun isLoaded(model: RAModelInfo): Boolean = model.isBuiltIn || state.currentModelId == model.id

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
        // A download begins by unloading resident weights to clear the RAM its preflight needs.
        // Auto-loading a chat model while one is in flight puts that memory straight back and can
        // fail the very transfer that freed it — and leaves the picker claiming a model is Loaded
        // beside a row that just said it was unloading everything.
        if (ModelDownloadService.active.value != null) return
        val ready = models.filter { isReady(it) && !it.isBuiltIn }
        // Default to the recommended chat model (Qwen3.5-0.8B — best on-device multi-turn recall) instead
        // of whatever happens to be first in the list; degrade through the other strong NPU chat models,
        // then any ready model. Mirrors ModelRecommendation.npuLLMs order.
        val candidateId = ModelAutoLoadPolicy.preferredCandidateId(ready.map { it.id }) ?: return
        val candidate = ready.first { it.id == candidateId }
        runCatching {
            RunAnywhere.models.load(candidate.id)
            RuntimeModelSelection.queryCurrent(context, models)
            GlobalState.lora.set(null)
        }.onFailure { RACLog.w("auto-load skipped: ${candidate.id}") }
    }

    class Factory(private val context: ModelSelectionContext) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            ModelSelectionViewModel(context) as T
    }
}
