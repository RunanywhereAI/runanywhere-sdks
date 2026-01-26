package com.runanywhere.runanywhereai.benchmark

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.availableModels
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * ViewModel for benchmark UI
 */
class BenchmarkViewModel(application: Application) : AndroidViewModel(application) {
    
    // MARK: - Dependencies
    
    private val app = application as RunAnywhereApplication
    val benchmarkService = BenchmarkService(application)
    
    // MARK: - UI State
    
    private val _uiState = MutableStateFlow(BenchmarkUiState())
    val uiState: StateFlow<BenchmarkUiState> = _uiState.asStateFlow()
    
    init {
        // Load available models
        viewModelScope.launch {
            loadAvailableModels()
        }
    }
    
    // MARK: - Actions
    
    fun startBenchmark() {
        val selectedIds = _uiState.value.selectedModelIds.toList()
        if (selectedIds.isEmpty()) return
        
        viewModelScope.launch {
            try {
                benchmarkService.runLLMBenchmark(
                    modelIds = selectedIds,
                    config = _uiState.value.selectedConfig.config
                )
            } catch (e: Exception) {
                // Error is handled by benchmarkService
            }
        }
    }
    
    fun cancelBenchmark() {
        benchmarkService.cancel()
    }
    
    fun clearResults() {
        benchmarkService.clearResults()
    }
    
    fun toggleModelSelection(modelId: String) {
        _uiState.update { state ->
            val newSelection = state.selectedModelIds.toMutableSet()
            if (newSelection.contains(modelId)) {
                newSelection.remove(modelId)
            } else {
                newSelection.add(modelId)
            }
            state.copy(selectedModelIds = newSelection)
        }
    }
    
    fun selectAllModels() {
        _uiState.update { state ->
            state.copy(selectedModelIds = state.availableModels.map { it.id }.toSet())
        }
    }
    
    fun deselectAllModels() {
        _uiState.update { state ->
            state.copy(selectedModelIds = emptySet())
        }
    }
    
    fun setSelectedConfig(config: ConfigOption) {
        _uiState.update { it.copy(selectedConfig = config) }
    }
    
    private suspend fun loadAvailableModels() {
        if (!app.isSDKReady()) return
        
        val models = RunAnywhere.availableModels().filter { model ->
            model.category == ModelCategory.LANGUAGE && model.isDownloaded
        }
        
        _uiState.update { it.copy(availableModels = models) }
    }
    
    // MARK: - Formatting Helpers
    
    fun formatTokensPerSecond(value: Double): String {
        return String.format(Locale.US, "%.1f tok/s", value)
    }
    
    fun formatLatency(ms: Double): String {
        return if (ms >= 1000) {
            String.format(Locale.US, "%.2fs", ms / 1000)
        } else {
            String.format(Locale.US, "%.0fms", ms)
        }
    }
    
    fun formatMemory(bytes: Long): String {
        val mb = bytes.toDouble() / 1024 / 1024
        return String.format(Locale.US, "%.0f MB", mb)
    }
    
    fun formatProgress(progress: Float): String {
        return String.format(Locale.US, "%.0f%%", progress * 100)
    }
    
    fun formatDuration(ms: Long): String {
        val seconds = ms / 1000
        val minutes = seconds / 60
        val secs = seconds % 60
        return if (minutes > 0) {
            "${minutes}m ${secs}s"
        } else {
            "${secs}s"
        }
    }
}

/**
 * UI state for benchmark screen
 */
data class BenchmarkUiState(
    val availableModels: List<ModelInfo> = emptyList(),
    val selectedModelIds: Set<String> = emptySet(),
    val selectedConfig: ConfigOption = ConfigOption.DEFAULT,
) {
    val canStartBenchmark: Boolean
        get() = selectedModelIds.isNotEmpty()
}

/**
 * Configuration options
 */
enum class ConfigOption(
    val displayName: String,
    val description: String,
    val config: BenchmarkConfig,
) {
    QUICK(
        displayName = "Quick",
        description = "1 warmup, 3 iterations, 1 prompt",
        config = BenchmarkConfig.QUICK
    ),
    DEFAULT(
        displayName = "Default",
        description = "3 warmups, 5 iterations, 3 prompts",
        config = BenchmarkConfig.DEFAULT
    ),
    COMPREHENSIVE(
        displayName = "Comprehensive",
        description = "3 warmups, 10 iterations, 3 prompts, more tokens",
        config = BenchmarkConfig.COMPREHENSIVE
    );
}
