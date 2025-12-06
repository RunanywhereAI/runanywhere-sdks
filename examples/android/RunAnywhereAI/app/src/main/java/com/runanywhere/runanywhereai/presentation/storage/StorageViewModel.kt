package com.runanywhere.runanywhereai.presentation.storage

import android.app.Application
import android.text.format.Formatter
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.sdk.models.storage.StoredModel
import com.runanywhere.sdk.public.extensions.clearCache
import com.runanywhere.sdk.public.extensions.cleanTempFiles
import com.runanywhere.sdk.public.extensions.deleteStoredModel
import com.runanywhere.sdk.public.extensions.getStorageInfo
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Storage UI State
 * Matches iOS StorageViewModel published properties exactly
 *
 * iOS Reference: StorageViewModel.swift
 */
data class StorageUiState(
    val totalStorageSize: Long = 0L,        // Total app storage usage (bytes)
    val availableSpace: Long = 0L,          // Device free space (bytes)
    val modelStorageSize: Long = 0L,        // Total size of downloaded models (bytes)
    val storedModels: List<StoredModel> = emptyList(),
    val storedModelsCount: Int = 0,         // For display
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

/**
 * StorageViewModel matching iOS StorageViewModel exactly
 *
 * iOS Reference: Features/Storage/StorageViewModel.swift
 *
 * This ViewModel manages:
 * - Storage usage information via RunAnywhere.getStorageInfo()
 * - Downloaded/stored models list
 * - Model deletion via RunAnywhere.deleteStoredModel()
 * - Cache and temp file cleanup via RunAnywhere.clearCache() and cleanTempFiles()
 */
class StorageViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as RunAnywhereApplication

    private val _uiState = MutableStateFlow(StorageUiState())
    val uiState: StateFlow<StorageUiState> = _uiState.asStateFlow()

    companion object {
        private const val TAG = "StorageViewModel"
    }

    init {
        loadData()
    }

    /**
     * Load storage data from SDK
     *
     * iOS equivalent:
     * func loadData() async {
     *     let storageInfo = await RunAnywhere.getStorageInfo()
     *     totalStorageSize = storageInfo.appStorage.totalSize
     *     availableSpace = storageInfo.deviceStorage.freeSpace
     *     modelStorageSize = storageInfo.modelStorage.totalSize
     *     storedModels = storageInfo.storedModels
     * }
     */
    fun loadData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }

            try {
                Log.d(TAG, "Loading storage info from SDK...")

                // Use SDK's getStorageInfo() - matches iOS exactly
                val storageInfo = RunAnywhere.getStorageInfo()

                Log.d(TAG, "Storage info received:")
                Log.d(TAG, "  - App total size: ${storageInfo.appStorage.totalSize}")
                Log.d(TAG, "  - Device free space: ${storageInfo.deviceStorage.freeSpace}")
                Log.d(TAG, "  - Model storage size: ${storageInfo.modelStorage.totalSize}")
                Log.d(TAG, "  - Stored models count: ${storageInfo.storedModels.size}")

                _uiState.update {
                    it.copy(
                        totalStorageSize = storageInfo.appStorage.totalSize,
                        availableSpace = storageInfo.deviceStorage.freeSpace,
                        modelStorageSize = storageInfo.modelStorage.totalSize,
                        storedModels = storageInfo.storedModels,
                        storedModelsCount = storageInfo.storedModels.size,
                        isLoading = false
                    )
                }

                Log.d(TAG, "Storage data loaded successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load storage data", e)
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
     * iOS equivalent: func refreshData() async { await loadData() }
     */
    fun refreshData() {
        loadData()
    }

    /**
     * Clear app cache
     *
     * iOS equivalent:
     * func clearCache() async {
     *     try await RunAnywhere.clearCache()
     *     await refreshData()
     * }
     */
    fun clearCache() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Clearing cache...")
                RunAnywhere.clearCache()
                Log.d(TAG, "Cache cleared successfully")
                refreshData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear cache", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to clear cache: ${e.message}")
                }
            }
        }
    }

    /**
     * Clean temporary files
     *
     * iOS equivalent:
     * func cleanTempFiles() async {
     *     try await RunAnywhere.cleanTempFiles()
     *     await refreshData()
     * }
     */
    fun cleanTempFiles() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Cleaning temp files...")
                RunAnywhere.cleanTempFiles()
                Log.d(TAG, "Temp files cleaned successfully")
                refreshData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clean temp files", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to clean temporary files: ${e.message}")
                }
            }
        }
    }

    /**
     * Delete a stored model
     *
     * iOS equivalent:
     * func deleteModel(_ modelId: String) async {
     *     try await RunAnywhere.deleteStoredModel(modelId)
     *     await refreshData()
     * }
     */
    fun deleteModel(modelId: String) {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Deleting model: $modelId")
                RunAnywhere.deleteStoredModel(modelId)
                Log.d(TAG, "Model deleted successfully: $modelId")
                refreshData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete model: $modelId", e)
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
