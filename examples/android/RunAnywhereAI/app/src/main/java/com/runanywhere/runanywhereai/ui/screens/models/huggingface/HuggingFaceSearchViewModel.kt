package com.runanywhere.runanywhereai.ui.screens.models.huggingface

import ai.runanywhere.proto.v1.InferenceFramework
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.hf.HfModelSummary
import com.runanywhere.runanywhereai.data.hf.HfRepoFile
import com.runanywhere.runanywhereai.data.hf.HfSearchKind
import com.runanywhere.runanywhereai.data.hf.HuggingFaceHubClient
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.downloadModelStream
import com.runanywhere.sdk.public.extensions.registerModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/** Where the search flow currently is. Download progress is tracked separately. */
enum class HuggingFacePhase { IDLE, SEARCHING, RESULTS, LOADING_FILES, REPO_DETAIL }

data class HuggingFaceSearchState(
    val query: String = "",
    val phase: HuggingFacePhase = HuggingFacePhase.IDLE,
    val results: List<HfModelSummary> = emptyList(),
    val selectedRepo: String? = null,
    val files: List<HfRepoFile> = emptyList(),
    val downloadingPath: String? = null,
    val downloadProgress: Int? = null,
    // Set once a download completes so the host can refresh the model list.
    val addedModelId: String? = null,
    val error: String? = null,
)

/**
 * Drives the "Add from Hugging Face" flow: search repos, list a repo's GGUF
 * quantizations, then register + download the chosen file through the existing
 * SDK path. The SDK resolves the HF file URL and streams the download — this VM
 * only wires the small REST search client to the picker UI.
 */
class HuggingFaceSearchViewModel : ViewModel() {

    private val client = HuggingFaceHubClient()

    private val _state = MutableStateFlow(HuggingFaceSearchState())
    val state: StateFlow<HuggingFaceSearchState> = _state.asStateFlow()

    private var searchJob: Job? = null
    private var filesJob: Job? = null
    private var downloadJob: Job? = null

    fun onQueryChange(query: String) {
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

    /** Returns to the results list from a repo detail view. */
    fun backToResults() {
        filesJob?.cancel()
        _state.update {
            it.copy(phase = HuggingFacePhase.RESULTS, selectedRepo = null, files = emptyList(), error = null)
        }
    }

    fun download(repoId: String, file: HfRepoFile) {
        if (_state.value.downloadingPath != null) return
        downloadJob?.cancel()
        downloadJob = viewModelScope.launch {
            val name = "${repoId.substringAfterLast('/')} (${file.quantLabel})"
            val url = "https://huggingface.co/$repoId/resolve/main/${file.path}"
            _state.update { it.copy(downloadingPath = file.path, downloadProgress = 0, error = null) }
            try {
                val model = RunAnywhere.registerModel(
                    name = name,
                    url = url,
                    framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                    memoryRequirement = file.sizeBytes.takeIf { it > 0 },
                )
                RunAnywhere.downloadModelStream(model).collect { p ->
                    val pct = if (p.total_bytes > 0) {
                        (p.bytes_downloaded * 100 / p.total_bytes).toInt()
                    } else {
                        (p.stage_progress.coerceIn(0f, 1f) * 100).toInt()
                    }
                    _state.update { it.copy(downloadProgress = pct) }
                }
                _state.update {
                    it.copy(downloadingPath = null, downloadProgress = null, addedModelId = model.id)
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

    /** Consume the one-shot completion signal after the host has refreshed its list. */
    fun clearAdded() {
        _state.update { it.copy(addedModelId = null) }
    }

    fun clearError() {
        _state.update { it.copy(error = null) }
    }
}
