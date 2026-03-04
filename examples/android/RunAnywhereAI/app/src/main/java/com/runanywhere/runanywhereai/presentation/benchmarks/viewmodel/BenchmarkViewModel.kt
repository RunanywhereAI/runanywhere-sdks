package com.runanywhere.runanywhereai.presentation.benchmarks.viewmodel

import android.app.Application
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkCategory
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkDeviceInfo
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkRun
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkRunStatus
import com.runanywhere.runanywhereai.presentation.benchmarks.models.BenchmarkStore
import com.runanywhere.runanywhereai.presentation.benchmarks.services.BenchmarkRunner
import com.runanywhere.runanywhereai.presentation.benchmarks.services.BenchmarkRunnerError
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.BenchmarkExportFormat
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.BenchmarkReportFormatter
import com.runanywhere.runanywhereai.presentation.benchmarks.utilities.SyntheticInputGenerator
import com.runanywhere.sdk.models.DeviceInfo
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File

// -- UI State --

data class BenchmarkUiState(
    val isRunning: Boolean = false,
    val progress: Float = 0f,
    val currentScenario: String = "",
    val currentModel: String = "",
    val completedCount: Int = 0,
    val totalCount: Int = 0,
    val pastRuns: List<BenchmarkRun> = emptyList(),
    val selectedCategories: Set<BenchmarkCategory> = BenchmarkCategory.entries.toSet(),
    val errorMessage: String? = null,
    val showClearConfirmation: Boolean = false,
    val copiedToastMessage: String? = null,
    val skippedCategoriesMessage: String? = null,
)

/**
 * Orchestrates benchmark execution, persistence, and export.
 * Matches iOS BenchmarkViewModel exactly.
 */
class BenchmarkViewModel(application: Application) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(BenchmarkUiState())
    val uiState: StateFlow<BenchmarkUiState> = _uiState.asStateFlow()

    private val runner = BenchmarkRunner()
    private val store = BenchmarkStore(application)
    private var runJob: Job? = null

    init {
        loadPastRuns()
    }

    // -- Lifecycle --

    fun loadPastRuns() {
        _uiState.update { it.copy(pastRuns = store.loadRuns().reversed()) }
    }

    // -- Category Toggle --

    fun toggleCategory(category: BenchmarkCategory) {
        _uiState.update { state ->
            val updated = state.selectedCategories.toMutableSet()
            if (category in updated) updated.remove(category) else updated.add(category)
            state.copy(selectedCategories = updated)
        }
    }

    fun selectAllCategories() {
        _uiState.update { it.copy(selectedCategories = BenchmarkCategory.entries.toSet()) }
    }

    // -- Run --

    fun runBenchmarks() {
        if (_uiState.value.isRunning) return

        _uiState.update {
            it.copy(
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
            val deviceInfo = makeDeviceInfo()
            var run = BenchmarkRun(deviceInfo = deviceInfo)

            try {
                val runResult = runner.runBenchmarks(
                    categories = _uiState.value.selectedCategories,
                ) { update ->
                    _uiState.update { state ->
                        state.copy(
                            progress = update.progress,
                            completedCount = update.completedCount,
                            totalCount = update.totalCount,
                            currentScenario = update.currentScenario,
                            currentModel = update.currentModel,
                        )
                    }
                }

                if (runResult.skippedCategories.isNotEmpty()) {
                    val names = runResult.skippedCategories.joinToString { it.displayName }
                    _uiState.update { it.copy(skippedCategoriesMessage = "Skipped (no models): $names") }
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
                _uiState.update { it.copy(errorMessage = e.message) }
            } catch (e: Exception) {
                run = run.copy(
                    status = BenchmarkRunStatus.FAILED,
                    completedAt = System.currentTimeMillis(),
                )
                _uiState.update { it.copy(errorMessage = e.localizedMessage ?: e.message ?: "Unknown error") }
            }

            if (run.results.isNotEmpty() || run.status != BenchmarkRunStatus.RUNNING) {
                store.save(run)
            }
            loadPastRuns()
            _uiState.update { it.copy(isRunning = false) }
        }
    }

    fun cancel() {
        runJob?.cancel()
        runJob = null
    }

    // -- Clear --

    fun showClearConfirmation() {
        _uiState.update { it.copy(showClearConfirmation = true) }
    }

    fun dismissClearConfirmation() {
        _uiState.update { it.copy(showClearConfirmation = false) }
    }

    fun clearAllResults() {
        store.clearAll()
        _uiState.update { it.copy(pastRuns = emptyList(), showClearConfirmation = false) }
    }

    fun dismissError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    // -- Copy to Clipboard --

    fun copyToClipboard(run: BenchmarkRun, format: BenchmarkExportFormat) {
        val context = getApplication<Application>()
        val report = BenchmarkReportFormatter.formattedString(run, format, context)
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Benchmark Report", report))
        _uiState.update { it.copy(copiedToastMessage = "${format.displayName} copied!") }
        viewModelScope.launch {
            delay(2000)
            _uiState.update { it.copy(copiedToastMessage = null) }
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
}
