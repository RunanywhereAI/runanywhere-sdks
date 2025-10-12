package com.runanywhere.ai.models.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.ai.models.data.*
import com.runanywhere.ai.models.repository.ModelRepository
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

class ModelManagementViewModel(
    private val repository: ModelRepository
) : ViewModel() {

    // UI State
    private val _uiState = MutableStateFlow(ModelManagementUiState())
    val uiState: StateFlow<ModelManagementUiState> = _uiState.asStateFlow()

    // Models grouped by framework
    val modelsByFramework: StateFlow<Map<LLMFramework, List<ModelInfo>>> =
        repository.availableModels.map { models ->
            models.groupBy { model ->
                model.preferredFramework ?: LLMFramework.CUSTOM
            }
        }.stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = emptyMap()
        )

    // Available frameworks
    val availableFrameworks: StateFlow<List<LLMFramework>> =
        modelsByFramework.map { it.keys.toList() }
            .stateIn(
                scope = viewModelScope,
                started = SharingStarted.WhileSubscribed(5000),
                initialValue = emptyList()
            )

    // Current model
    val currentModel: StateFlow<ModelInfo?> = repository.currentModel

    // Download progress
    val downloadProgress: StateFlow<Map<String, Float>> = repository.downloadProgress

    // Loading state
    val isLoading: StateFlow<Boolean> = repository.isLoading

    init {
        refreshModels()
        observeRepositoryState()
    }

    private fun observeRepositoryState() {
        // Observe current model changes
        viewModelScope.launch {
            repository.currentModel.collect { model ->
                _uiState.update { it.copy(selectedModel = model) }
            }
        }
    }

    fun refreshModels() {
        viewModelScope.launch {
            _uiState.update { it.copy(isRefreshing = true, error = null) }
            try {
                repository.refreshModels()
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(error = "Failed to refresh models: ${e.message}")
                }
            } finally {
                _uiState.update { it.copy(isRefreshing = false) }
            }
        }
    }

    fun selectFramework(framework: LLMFramework?) {
        _uiState.update {
            it.copy(
                selectedFramework = framework,
                expandedFramework = if (framework == it.expandedFramework) null else framework
            )
        }
    }

    fun toggleFrameworkExpansion(framework: LLMFramework) {
        _uiState.update { state ->
            state.copy(
                expandedFramework = if (state.expandedFramework == framework) null else framework
            )
        }
    }

    fun downloadModel(modelId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(downloadingModels = it.downloadingModels + modelId) }
            try {
                repository.downloadModel(modelId).collect { progress ->
                    // Progress is already being tracked in repository
                }
                _uiState.update {
                    it.copy(
                        downloadingModels = it.downloadingModels - modelId,
                        message = "Model downloaded successfully"
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        downloadingModels = it.downloadingModels - modelId,
                        error = "Download failed: ${e.message}"
                    )
                }
            }
        }
    }

    fun loadModel(modelId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(loadingModel = modelId) }
            try {
                repository.loadModel(modelId)
                _uiState.update {
                    it.copy(
                        loadingModel = null,
                        message = "Model loaded successfully"
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        loadingModel = null,
                        error = "Failed to load model: ${e.message}"
                    )
                }
            }
        }
    }

    fun deleteModel(modelId: String) {
        viewModelScope.launch {
            try {
                repository.deleteModel(modelId)
                _uiState.update {
                    it.copy(message = "Model deleted successfully")
                }
                refreshModels()
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(error = "Failed to delete model: ${e.message}")
                }
            }
        }
    }

    fun showModelDetails(model: ModelInfo) {
        _uiState.update { it.copy(selectedModelForDetails = model) }
    }

    fun hideModelDetails() {
        _uiState.update { it.copy(selectedModelForDetails = null) }
    }

    fun showAddModelDialog() {
        _uiState.update { it.copy(showAddModelDialog = true) }
    }

    fun hideAddModelDialog() {
        _uiState.update { it.copy(showAddModelDialog = false) }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    suspend fun getStorageInfo(): StorageInfo {
        return repository.getStorageInfo()
    }

    fun clearCache() {
        viewModelScope.launch {
            try {
                repository.clearCache()
                _uiState.update {
                    it.copy(message = "Cache cleared successfully")
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(error = "Failed to clear cache: ${e.message}")
                }
            }
        }
    }
}

data class ModelManagementUiState(
    val selectedFramework: LLMFramework? = null,
    val expandedFramework: LLMFramework? = null,
    val selectedModel: ModelInfo? = null,
    val selectedModelForDetails: ModelInfo? = null,
    val downloadingModels: Set<String> = emptySet(),
    val loadingModel: String? = null,
    val isRefreshing: Boolean = false,
    val showAddModelDialog: Boolean = false,
    val message: String? = null,
    val error: String? = null
)
