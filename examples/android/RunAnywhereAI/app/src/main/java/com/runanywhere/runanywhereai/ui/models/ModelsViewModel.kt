package com.runanywhere.runanywhereai.ui.models

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.repository.DownloadProgress
import com.runanywhere.runanywhereai.data.repository.ModelInfo
import com.runanywhere.runanywhereai.data.repository.ModelRepository
import com.runanywhere.runanywhereai.ui.chat.ChatViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * ViewModel for models management screen
 */
class ModelsViewModel(application: Application) : AndroidViewModel(application) {

    private val modelRepository = ModelRepository(application)

    private val _availableModels = MutableStateFlow<List<ModelInfo>>(emptyList())
    val availableModels: StateFlow<List<ModelInfo>> = _availableModels.asStateFlow()

    private val _downloadedModels = MutableStateFlow<List<ModelInfo>>(emptyList())
    val downloadedModels: StateFlow<List<ModelInfo>> = _downloadedModels.asStateFlow()

    private val _downloadProgress = MutableStateFlow<ModelDownloadProgress?>(null)
    val downloadProgress: StateFlow<ModelDownloadProgress?> = _downloadProgress.asStateFlow()

    private val _selectedModel = MutableStateFlow<ModelInfo?>(null)
    val selectedModel: StateFlow<ModelInfo?> = _selectedModel.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        refreshModels()
    }

    /**
     * Refresh available and downloaded models
     */
    fun refreshModels() {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null

            try {
                // Get available models
                _availableModels.value = modelRepository.getAvailableModels()

                // Get downloaded models
                _downloadedModels.value = modelRepository.getDownloadedModels()

                // Check if selected model is still available
                _selectedModel.value?.let { selected ->
                    if (_downloadedModels.value.none { it.id == selected.id }) {
                        _selectedModel.value = null
                    }
                }
            } catch (e: Exception) {
                _error.value = "Failed to refresh models: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * Download a model
     */
    fun downloadModel(model: ModelInfo) {
        viewModelScope.launch {
            _error.value = null

            modelRepository.downloadModel(model).collect { progress ->
                _downloadProgress.value = ModelDownloadProgress(model.id, progress)

                // Refresh models when download completes
                if (progress is DownloadProgress.Completed || progress is DownloadProgress.Failed) {
                    refreshModels()

                    // Clear progress after a delay
                    kotlinx.coroutines.delay(2000)
                    if (_downloadProgress.value?.modelId == model.id) {
                        _downloadProgress.value = null
                    }
                }
            }
        }
    }

    /**
     * Delete a downloaded model
     */
    fun deleteModel(model: ModelInfo) {
        viewModelScope.launch {
            _error.value = null

            try {
                val success = modelRepository.deleteModel(model)
                if (success) {
                    // If this was the selected model, clear selection
                    if (_selectedModel.value?.id == model.id) {
                        _selectedModel.value = null
                    }
                    refreshModels()
                } else {
                    _error.value = "Failed to delete model"
                }
            } catch (e: Exception) {
                _error.value = "Failed to delete model: ${e.message}"
            }
        }
    }

    /**
     * Select a model for use
     */
    fun selectModel(model: ModelInfo) {
        if (model.isDownloaded) {
            _selectedModel.value = model

            // Note: In a real app, you'd communicate this selection
            // to the ChatViewModel through a shared repository or event bus
        }
    }

    /**
     * Get currently selected model
     */
    fun getSelectedModel(): ModelInfo? {
        return _selectedModel.value
    }
}
