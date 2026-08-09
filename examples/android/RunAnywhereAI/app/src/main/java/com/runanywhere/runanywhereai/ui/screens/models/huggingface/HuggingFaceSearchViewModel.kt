package com.runanywhere.runanywhereai.ui.screens.models.huggingface

import ai.runanywhere.proto.v1.InferenceFramework
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.hf.HfModelSummary
import com.runanywhere.runanywhereai.data.hf.HfRepoFile
import com.runanywhere.runanywhereai.data.hf.HfSearchKind
import com.runanywhere.runanywhereai.data.hf.HfSuggestedModel
import com.runanywhere.runanywhereai.data.hf.HuggingFaceCatalog
import com.runanywhere.runanywhereai.data.hf.HuggingFaceHubClient
import com.runanywhere.runanywhereai.download.DownloadProgressInfo
import com.runanywhere.runanywhereai.download.DownloadUpdate
import com.runanywhere.runanywhereai.download.ModelDownloadService
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.ModelRegistration
import com.runanywhere.sdk.public.api.models
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/**
 * Where the search flow currently is. Download progress is tracked separately.
 *
 * [IDLE] is not an empty screen: it is the curated suggestion list, which is what the sheet
 * opens on and what it returns to whenever the query is emptied.
 */
enum class HuggingFacePhase { IDLE, SEARCHING, RESULTS, LOADING_FILES, REPO_DETAIL }

data class HuggingFaceSearchState(
    val query: String = "",
    val phase: HuggingFacePhase = HuggingFacePhase.IDLE,
    /**
     * Authored sub-1B repos shown in [HuggingFacePhase.IDLE]. Constant for the session — it
     * lives in state so the composable reads one source of truth instead of reaching into
     * the catalog itself.
     */
    val suggestions: List<HfSuggestedModel> = HuggingFaceCatalog.ggufUnder1B,
    val results: List<HfModelSummary> = emptyList(),
    val selectedRepo: String? = null,
    val files: List<HfRepoFile> = emptyList(),
    val downloadingPath: String? = null,
    val downloadProgress: DownloadProgressInfo? = null,
    // Set once a download completes so the host can refresh the model list.
    val addedModelId: String? = null,
    val error: String? = null,
)

/**
 * Drives the "Add from Hugging Face" flow: offer curated sub-1B suggestions, search repos,
 * list a repo's GGUF quantizations, then register + download the chosen file through the
 * existing SDK path. The SDK resolves the HF file URL and streams the download — this VM
 * only wires the small REST search client to the picker UI.
 *
 * A suggestion and a search hit converge on [openRepo]: there is exactly one download path.
 */
class HuggingFaceSearchViewModel : ViewModel() {

    private val client = HuggingFaceHubClient()

    private val _state = MutableStateFlow(HuggingFaceSearchState())
    val state: StateFlow<HuggingFaceSearchState> = _state.asStateFlow()

    private var searchJob: Job? = null
    private var filesJob: Job? = null
    private var downloadJob: Job? = null

    /**
     * Emptying the field is a state transition, not just a blank render: any in-flight search
     * is abandoned and the sheet goes back to the suggestions it opened with. Handling this
     * only in the composable would leave a stale RESULTS phase behind the empty field.
     *
     * The previous [HuggingFaceSearchState.results] are intentionally kept — they are not
     * shown in IDLE, and holding them means the panel crossfade animates out the list the
     * user was actually looking at rather than a "no models match" flash.
     */
    fun onQueryChange(query: String) {
        if (query.isBlank()) {
            searchJob?.cancel()
            _state.update { it.copy(query = query, phase = HuggingFacePhase.IDLE, error = null) }
            return
        }
        _state.update { it.copy(query = query) }
    }

    fun search() {
        val query = _state.value.query.trim()
        if (query.isEmpty()) return
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            _state.update {
                it.copy(
                    phase = HuggingFacePhase.SEARCHING,
                    selectedRepo = null,
                    files = emptyList(),
                    error = null,
                )
            }
            try {
                val results = client.searchModels(query, HfSearchKind.GGUF)
                _state.update { it.copy(phase = HuggingFacePhase.RESULTS, results = results) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("hf search failed: $query", e)
                _state.update {
                    it.copy(phase = HuggingFacePhase.RESULTS, error = e.message ?: "Search failed")
                }
            }
        }
    }

    fun openRepo(repoId: String) {
        filesJob?.cancel()
        filesJob = viewModelScope.launch {
            _state.update {
                it.copy(
                    phase = HuggingFacePhase.LOADING_FILES,
                    selectedRepo = repoId,
                    files = emptyList(),
                    error = null,
                )
            }
            try {
                val files = client.listGgufFiles(repoId)
                _state.update { it.copy(phase = HuggingFacePhase.REPO_DETAIL, files = files) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("hf file list failed: $repoId", e)
                _state.update {
                    it.copy(phase = HuggingFacePhase.REPO_DETAIL, error = e.message ?: "Could not load files")
                }
            }
        }
    }

    /**
     * Leaves a repo detail view for wherever the repo was opened from. A suggestion can only
     * be tapped while the field is empty and a search result only while it is not, so the
     * query alone tells the two entry points apart without a second flag.
     *
     * [HuggingFaceSearchState.files] survive for the same reason the results do above: the
     * outgoing half of the panel crossfade should show the file list, not "no GGUF files".
     */
    fun back() {
        filesJob?.cancel()
        val hasQuery = _state.value.query.isNotBlank()
        _state.update {
            it.copy(
                phase = if (hasQuery) HuggingFacePhase.RESULTS else HuggingFacePhase.IDLE,
                selectedRepo = null,
                error = null,
            )
        }
    }

    fun download(repoId: String, file: HfRepoFile) {
        if (_state.value.downloadingPath != null) return
        downloadJob?.cancel()
        downloadJob = viewModelScope.launch {
            val name = "${repoId.substringAfterLast('/')} (${file.quantLabel})"
            val url = "https://huggingface.co/$repoId/resolve/main/${file.path}"
            _state.update { it.copy(downloadingPath = file.path, downloadProgress = DownloadProgressInfo(), error = null) }
            try {
                val model = RunAnywhere.models.register(
                    ModelRegistration.url(
                        name = name,
                        url = url,
                        framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                        memoryBytes = file.sizeBytes.takeIf { it > 0 },
                    ),
                )
                // Same foreground service the model picker uses. A community GGUF is the same
                // several gigabytes as a catalogue one, so it gets the same wake lock, the same
                // progress notification and the same survival when the user leaves the app —
                // downloading it inside this sheet's scope meant closing the sheet lost it.
                val stopped = if (ModelDownloadService.start(model)) {
                    awaitForegroundDownload(model.id)
                } else {
                    downloadInProcess(model.id)
                }
                _state.update {
                    it.copy(
                        downloadingPath = null,
                        downloadProgress = null,
                        addedModelId = model.id.takeIf { stopped == null },
                        error = stopped?.message,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("hf download failed: $url", e)
                _state.update {
                    it.copy(
                        downloadingPath = null,
                        downloadProgress = null,
                        error = e.message ?: "Download failed",
                    )
                }
            }
        }
    }

    /**
     * Mirror the foreground service's transfer of [modelId] into this sheet, and return how it
     * ended — null when the bytes are all on disk.
     *
     * The progress mirror is a child job rather than a `takeWhile`, so the wait for the terminal
     * state and the drawing of the bar cannot disagree about which snapshot was the last one.
     *
     * The ending comes from the outcome [ModelDownloadService.awaitFinish] returns rather than from
     * sampling the interruption map afterwards: the record is written by the job that owned the
     * transfer, and sampling raced it — a transfer preempted by a second start had not recorded
     * anything yet, so the sheet announced an abandoned download as an added model.
     */
    private suspend fun awaitForegroundDownload(modelId: String): ModelDownloadService.Interrupted? =
        coroutineScope {
            val mirror = launch {
                ModelDownloadService.active.collect { snapshot ->
                    if (snapshot?.modelId == modelId) {
                        _state.update { it.copy(downloadProgress = snapshot.progress) }
                    }
                }
            }
            val outcome = ModelDownloadService.awaitFinish(modelId)
            mirror.cancel()
            (outcome as? ModelDownloadService.Outcome.Stopped)?.record
        }

    /**
     * The fallback for when the foreground service cannot be started (the app is already in the
     * background). No wake lock and it dies with this ViewModel, so it is a last resort — but it
     * reports the same outcome, and records the same resume point, as the service path.
     */
    private suspend fun downloadInProcess(modelId: String): ModelDownloadService.Interrupted? {
        var latest = DownloadProgressInfo()
        // The SDK reports a failure as a terminal event and then ends the stream normally, so
        // reaching the end of the stream is not on its own proof the file arrived. This used to
        // announce the repo as added over a download that never finished.
        var stopped: ModelDownloadService.Interrupted? = null
        RunAnywhere.models.download(modelId).collect { event ->
            when (val update = DownloadProgressInfo.advance(latest, event)) {
                is DownloadUpdate.Advanced -> {
                    latest = update.info
                    _state.update { it.copy(downloadProgress = update.info) }
                }
                is DownloadUpdate.Stopped -> stopped = ModelDownloadService.Interrupted(
                    cancelled = update.cancelled,
                    message = update.message,
                    progress = latest.takeIf { it.bytesDone > 0 },
                )
                DownloadUpdate.Finished, DownloadUpdate.Ignored -> Unit
            }
        }
        stopped?.let {
            ModelDownloadService.noteInterrupted(modelId, it.cancelled, it.message, it.progress)
        }
        return stopped
    }

    /** Consume the one-shot completion signal after the host has refreshed its list. */
    fun clearAdded() {
        _state.update { it.copy(addedModelId = null) }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }
}
