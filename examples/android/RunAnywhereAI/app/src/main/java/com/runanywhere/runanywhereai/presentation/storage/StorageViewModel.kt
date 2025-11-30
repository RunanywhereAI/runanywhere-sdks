package com.runanywhere.runanywhereai.presentation.storage

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Stored Model Information
 * iOS Reference: StoredModel in StorageViewModel.swift
 */
data class StoredModelInfo(
    val id: String,
    val name: String,
    val format: String,
    val framework: String?,
    val size: Long,
    val path: String,
    val createdDate: Long,
    val lastUsed: Long? = null,
    val contextLength: Int? = null
)

/**
 * Storage UI State
 * iOS Reference: StorageViewModel published properties
 */
data class StorageUiState(
    val totalStorageSize: Long = 0L,
    val availableSpace: Long = 0L,
    val modelStorageSize: Long = 0L,
    val storedModels: List<StoredModelInfo> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

/**
 * StorageViewModel matching iOS StorageViewModel
 *
 * iOS Reference: StorageViewModel.swift
 *
 * This ViewModel manages:
 * - Storage usage information
 * - Downloaded/stored models list
 * - Model deletion
 * - Cache and temp file cleanup
 *
 * TODO: Integrate with RunAnywhere SDK when storage APIs are available
 */
class StorageViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as RunAnywhereApplication

    private val _uiState = MutableStateFlow(StorageUiState())
    val uiState: StateFlow<StorageUiState> = _uiState.asStateFlow()

    init {
        loadData()
    }

    /**
     * Load storage data
     *
     * TODO: Integrate with RunAnywhere SDK
     * iOS equivalent: RunAnywhere.getStorageInfo()
     */
    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }

            try {
                // TODO: Replace with actual SDK integration
                // iOS equivalent:
                // let storageInfo = await RunAnywhere.getStorageInfo()
                // totalStorageSize = storageInfo.appStorage.totalSize
                // availableSpace = storageInfo.deviceStorage.freeSpace
                // modelStorageSize = storageInfo.modelStorage.totalSize
                // storedModels = storageInfo.storedModels

                // Mock data for now - matches iOS mock pattern
                val mockModels = listOf(
                    StoredModelInfo(
                        id = "smollm2-135m",
                        name = "SmolLM2 135M",
                        format = "gguf",
                        framework = "LlamaCpp",
                        size = 135_000_000L,
                        path = "/data/models/smollm2-135m.gguf",
                        createdDate = System.currentTimeMillis() - 86400000,
                        contextLength = 2048
                    ),
                    StoredModelInfo(
                        id = "whisper-tiny",
                        name = "Whisper Tiny",
                        format = "gguf",
                        framework = "WhisperKit",
                        size = 75_000_000L,
                        path = "/data/models/whisper-tiny.gguf",
                        createdDate = System.currentTimeMillis() - 172800000
                    )
                )

                val totalModelSize = mockModels.sumOf { it.size }

                _uiState.update {
                    it.copy(
                        storedModels = mockModels,
                        totalStorageSize = totalModelSize + 50_000_000L, // Add cache
                        modelStorageSize = totalModelSize,
                        availableSpace = 10_000_000_000L, // 10 GB mock
                        isLoading = false
                    )
                }
            } catch (e: Exception) {
                Log.e("StorageViewModel", "Failed to load storage data", e)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        errorMessage = "Failed to load storage data: ${e.message}"
                    )
                }
            }
        }
    }

    /**
     * Refresh storage data
     *
     * iOS equivalent: storageViewModel.refreshData()
     */
    fun refreshData() {
        loadData()
    }

    /**
     * Clear app cache
     *
     * TODO: Integrate with RunAnywhere SDK
     * iOS equivalent: RunAnywhere.clearCache()
     */
    fun clearCache() {
        viewModelScope.launch {
            try {
                // TODO: Replace with actual SDK integration
                // iOS equivalent: try await RunAnywhere.clearCache()

                _uiState.update {
                    it.copy(
                        totalStorageSize = it.modelStorageSize // Remove cache from total
                    )
                }
                refreshData()
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(errorMessage = "Failed to clear cache: ${e.message}")
                }
            }
        }
    }

    /**
     * Clean temporary files
     *
     * TODO: Integrate with RunAnywhere SDK
     * iOS equivalent: RunAnywhere.cleanTempFiles()
     */
    fun cleanTempFiles() {
        viewModelScope.launch {
            try {
                // TODO: Replace with actual SDK integration
                // iOS equivalent: try await RunAnywhere.cleanTempFiles()

                refreshData()
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(errorMessage = "Failed to clean temporary files: ${e.message}")
                }
            }
        }
    }

    /**
     * Delete a stored model
     *
     * TODO: Integrate with RunAnywhere SDK
     * iOS equivalent: RunAnywhere.deleteStoredModel(modelId)
     */
    fun deleteModel(modelId: String) {
        viewModelScope.launch {
            try {
                // TODO: Replace with actual SDK integration
                // iOS equivalent: try await RunAnywhere.deleteStoredModel(modelId)

                _uiState.update { state ->
                    val filteredModels = state.storedModels.filter { it.id != modelId }
                    state.copy(
                        storedModels = filteredModels,
                        modelStorageSize = filteredModels.sumOf { it.size }
                    )
                }
                refreshData()
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(errorMessage = "Failed to delete model: ${e.message}")
                }
            }
        }
    }

    /**
     * Clear error message
     */
    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }
}
