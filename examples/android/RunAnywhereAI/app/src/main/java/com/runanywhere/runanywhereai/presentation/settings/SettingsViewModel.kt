package com.runanywhere.runanywhereai.presentation.settings

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.infrastructure.events.EventBus
import com.runanywhere.sdk.infrastructure.events.SDKModelEvent
import com.runanywhere.sdk.`public`.extensions.clearCache
import com.runanywhere.sdk.`public`.extensions.cleanTempFiles
import com.runanywhere.sdk.`public`.extensions.deleteModel
import com.runanywhere.sdk.`public`.extensions.getStorageInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Simple stored model info for settings display
 */
data class StoredModelInfo(
    val id: String,
    val name: String,
    val size: Long,
)

/**
 * Settings UI State
 */
@OptIn(kotlin.time.ExperimentalTime::class)
data class SettingsUiState(
    // Storage Overview
    val totalStorageSize: Long = 0L,
    val availableSpace: Long = 0L,
    val modelStorageSize: Long = 0L,
    // Downloaded Models
    val downloadedModels: List<StoredModelInfo> = emptyList(),
    // Loading states
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

/**
 * Settings ViewModel
 *
 * This ViewModel manages:
 * - Storage overview via RunAnywhere.getStorageInfo()
 * - Model management via RunAnywhere storage APIs
 */
class SettingsViewModel(application: Application) : AndroidViewModel(application) {
    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    companion object {
        private const val TAG = "SettingsViewModel"
    }

    init {
        loadStorageData()
        subscribeToModelEvents()
    }

    /**
     * Subscribe to SDK model events to automatically refresh storage when models are downloaded/deleted
     */
    private fun subscribeToModelEvents() {
        viewModelScope.launch {
            EventBus.modelEvents.collect { event ->
                when (event) {
                    is SDKModelEvent.DownloadCompleted -> {
                        Log.d(TAG, "📥 Model download completed: ${event.modelId}, refreshing storage...")
                        loadStorageData()
                    }
                    is SDKModelEvent.DeleteCompleted -> {
                        Log.d(TAG, "🗑️ Model deleted: ${event.modelId}, refreshing storage...")
                        loadStorageData()
                    }
                    else -> {
                        // Other events don't require storage refresh
                    }
                }
            }
        }
    }

    /**
     * Load storage data using SDK's getStorageInfo() API
     */
    private fun loadStorageData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            try {
                Log.d(TAG, "Loading storage info via getStorageInfo()...")

                // Use SDK's getStorageInfo()
                val storageInfo = getStorageInfo()

                // Map stored models to UI model
                val storedModels = storageInfo.storedModels.map { model ->
                    StoredModelInfo(
                        id = model.id,
                        name = model.name,
                        size = model.size,
                    )
                }

                Log.d(TAG, "Storage info received:")
                Log.d(TAG, "  - Total space: ${storageInfo.deviceStorage.totalSpace}")
                Log.d(TAG, "  - Free space: ${storageInfo.deviceStorage.freeSpace}")
                Log.d(TAG, "  - Model storage size: ${storageInfo.modelStorage.totalSize}")
                Log.d(TAG, "  - Stored models count: ${storedModels.size}")

                _uiState.update {
                    it.copy(
                        totalStorageSize = storageInfo.deviceStorage.totalSpace,
                        availableSpace = storageInfo.deviceStorage.freeSpace,
                        modelStorageSize = storageInfo.modelStorage.totalSize,
                        downloadedModels = storedModels,
                        isLoading = false,
                    )
                }

                Log.d(TAG, "Storage data loaded successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load storage data", e)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        errorMessage = "Failed to load storage data: ${e.message}",
                    )
                }
            }
        }
    }

    /**
     * Refresh storage data
     */
    fun refreshStorage() {
        loadStorageData()
    }

    /**
     * Delete a downloaded model
     */
    fun deleteModelById(modelId: String) {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Deleting model: $modelId")
                // Use SDK's deleteModel extension function
                com.runanywhere.sdk.public.extensions.deleteModel(modelId)
                Log.d(TAG, "Model deleted successfully: $modelId")

                // Refresh storage data after deletion
                loadStorageData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete model: $modelId", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to delete model: ${e.message}")
                }
            }
        }
    }

    /**
     * Clear cache using SDK's clearCache() API
     */
    fun clearCache() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Clearing cache via clearCache()...")
                clearCache()
                Log.d(TAG, "Cache cleared successfully")

                // Refresh storage data after clearing cache
                loadStorageData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear cache", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to clear cache: ${e.message}")
                }
            }
        }
    }

    /**
     * Clean temporary files using SDK's cleanTempFiles() API
     */
    fun cleanTempFiles() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Cleaning temp files via cleanTempFiles()...")
                cleanTempFiles()
                Log.d(TAG, "Temp files cleaned successfully")

                // Refresh storage data after cleaning
                loadStorageData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clean temp files", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to clean temporary files: ${e.message}")
                }
            }
        }
    }
}
