package com.runanywhere.runanywhereai.viewmodels

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.models.BenchmarkCategory
import com.runanywhere.runanywhereai.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.models.BenchmarkEvent
import com.runanywhere.runanywhereai.models.BenchmarkExportFormat
import com.runanywhere.runanywhereai.models.BenchmarkRun
import com.runanywhere.runanywhereai.models.BenchmarkRunStatus
import com.runanywhere.runanywhereai.models.BenchmarkUiState
import com.runanywhere.runanywhereai.services.BenchmarkReportFormatter
import com.runanywhere.runanywhereai.services.BenchmarkRunner
import com.runanywhere.runanywhereai.services.BenchmarkRunnerError
import com.runanywhere.runanywhereai.services.BenchmarkStore
import com.runanywhere.runanywhereai.services.SyntheticInputGenerator
import com.runanywhere.sdk.models.DeviceInfo
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class BenchmarkViewModel(application: Application) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow<BenchmarkUiState>(BenchmarkUiState.Ready())
    val uiState: StateFlow<BenchmarkUiState> = _uiState.asStateFlow()

    private val _events = Channel<BenchmarkEvent>(Channel.BUFFERED)
    val events: Flow<BenchmarkEvent> = _events.receiveAsFlow()

    private val runner = BenchmarkRunner()
    private val store = BenchmarkStore(application)
    private var runJob: Job? = null

    init {
        loadPastRuns()
    }

    // -- Lifecycle --

    fun loadPastRuns() {
        viewModelScope.launch(Dispatchers.IO) {
            val runs = store.loadRuns().reversed().toImmutableList()
            updateReady { copy(pastRuns = runs) }
        }
    }

    // -- Category Toggle --

    fun toggleCategory(category: BenchmarkCategory) {
        updateReady {
            val updated = selectedCategories.toMutableSet()
            if (category in updated) updated.remove(category) else updated.add(category)
            copy(selectedCategories = updated)
        }
    }

    fun selectAllCategories() {
        updateReady { copy(selectedCategories = BenchmarkCategory.entries.toSet()) }
    }

    // -- Run Benchmarks --

    fun runBenchmarks() {
        val state = (_uiState.value as? BenchmarkUiState.Ready) ?: return
        if (state.isRunning) return

        updateReady {
            copy(
                isRunning = true,
                errorMessage = null,
                skippedCategoriesMessage = null,
                progress = 0f,
                completedCount = 0,
                totalCount = 0,
                currentScenario = "Preparing...",
                currentModel = "",
            )
        }

        runJob = viewModelScope.launch {
            val deviceInfo = withContext(Dispatchers.IO) { makeDeviceInfo() }
            var run = BenchmarkRun(deviceInfo = deviceInfo)

            try {
                val runResult = withContext(Dispatchers.IO) {
                    runner.runBenchmarks(
                        categories = (_uiState.value as? BenchmarkUiState.Ready)?.selectedCategories
                            ?: BenchmarkCategory.entries.toSet(),
                    ) { progressUpdate ->
                        updateReady {
                            copy(
                                progress = progressUpdate.progress,
                                completedCount = progressUpdate.completedCount,
                                totalCount = progressUpdate.totalCount,
                                currentScenario = progressUpdate.currentScenario,
                                currentModel = progressUpdate.currentModel,
                            )
                        }
                    }
                }

                if (runResult.skippedCategories.isNotEmpty()) {
                    val names = runResult.skippedCategories.joinToString { it.displayName }
                    updateReady { copy(skippedCategoriesMessage = "Skipped (no models): $names") }
                }

                run = run.copy(
                    results = runResult.results,
                    status = BenchmarkRunStatus.COMPLETED,
                    completedAt = System.currentTimeMillis(),
                )
            } catch (_: kotlinx.coroutines.CancellationException) {
                run = run.copy(
                    status = BenchmarkRunStatus.CANCELLED,
                    completedAt = System.currentTimeMillis(),
                )
            } catch (e: BenchmarkRunnerError) {
                run = run.copy(
                    status = BenchmarkRunStatus.FAILED,
                    completedAt = System.currentTimeMillis(),
                )
                updateReady { copy(errorMessage = e.message) }
            } catch (e: Exception) {
                run = run.copy(
                    status = BenchmarkRunStatus.FAILED,
                    completedAt = System.currentTimeMillis(),
                )
                updateReady { copy(errorMessage = e.localizedMessage ?: e.message ?: "Unknown error") }
            }

            if (run.results.isNotEmpty() || run.status != BenchmarkRunStatus.RUNNING) {
                withContext(Dispatchers.IO) { store.save(run) }
            }
            loadPastRuns()
            updateReady { copy(isRunning = false) }
        }
    }

    fun cancel() {
        runJob?.cancel()
        runJob = null
    }

    // -- Clear --

    fun showClearConfirmation() {
        updateReady { copy(showClearConfirmation = true) }
    }

    fun dismissClearConfirmation() {
        updateReady { copy(showClearConfirmation = false) }
    }

    fun clearAllResults() {
        viewModelScope.launch(Dispatchers.IO) { store.clearAll() }
        updateReady {
            copy(
                pastRuns = emptyList<BenchmarkRun>().toImmutableList(),
                showClearConfirmation = false,
            )
        }
    }

    fun dismissError() {
        updateReady { copy(errorMessage = null) }
    }

    // -- Copy to Clipboard --

    fun copyToClipboard(run: BenchmarkRun, format: BenchmarkExportFormat) {
        val context = getApplication<Application>()
        val report = BenchmarkReportFormatter.formattedString(run, format, context)
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Benchmark Report", report))
        updateReady { copy(copiedToastMessage = "${format.displayName} copied!") }
        viewModelScope.launch {
            delay(2000)
            updateReady { copy(copiedToastMessage = null) }
        }
    }

    // -- File Export --

    fun shareFile(run: BenchmarkRun, csv: Boolean): Intent {
        val context = getApplication<Application>()
        val file: File = if (csv) {
            BenchmarkReportFormatter.writeCSV(run, context)
        } else {
            BenchmarkReportFormatter.writeJSON(run, context)
        }
        val uri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            file,
        )
        return Intent(Intent.ACTION_SEND).apply {
            type = if (csv) "text/csv" else "application/json"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    // -- Helpers --

    private fun makeDeviceInfo(): BenchmarkDeviceInfo {
        return try {
            val info = DeviceInfo.current
            BenchmarkDeviceInfo(
                modelName = info.modelName,
                chipName = info.architecture,
                totalMemoryBytes = info.totalMemory,
                availableMemoryBytes = SyntheticInputGenerator.availableMemoryBytes(),
                osVersion = "Android ${info.osVersion}",
            )
        } catch (_: Exception) {
            BenchmarkDeviceInfo(
                modelName = android.os.Build.MODEL,
                chipName = android.os.Build.HARDWARE,
                totalMemoryBytes = Runtime.getRuntime().maxMemory(),
                availableMemoryBytes = SyntheticInputGenerator.availableMemoryBytes(),
                osVersion = "Android ${android.os.Build.VERSION.RELEASE}",
            )
        }
    }

    /** Atomically update the [BenchmarkUiState.Ready] state. No-op if not Ready. */
    private inline fun updateReady(crossinline transform: BenchmarkUiState.Ready.() -> BenchmarkUiState.Ready) {
        _uiState.update { current ->
            when (current) {
                is BenchmarkUiState.Ready -> current.transform()
                else -> current
            }
        }
    }
}
