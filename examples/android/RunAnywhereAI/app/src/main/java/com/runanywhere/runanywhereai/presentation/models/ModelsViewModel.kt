package com.runanywhere.runanywhereai.presentation.models

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.models.collectDeviceInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * ViewModel for Models Screen - Manages device info, frameworks, and models
 * Matches iOS ModelListViewModel functionality
 */
class ModelsViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(ModelsUiState())
    val uiState: StateFlow<ModelsUiState> = _uiState.asStateFlow()

    init {
        loadDeviceInfo()
        loadFrameworksAndModels()
    }

    private fun loadDeviceInfo() {
        viewModelScope.launch {
            val deviceInfo = collectDeviceInfo()
            _uiState.update { it.copy(deviceInfo = deviceInfo) }
        }
    }

    private fun loadFrameworksAndModels() {
        viewModelScope.launch {
            try {
                // Load from SDK - NO MOCK DATA
                val sdkModels = com.runanywhere.sdk.public.RunAnywhere.availableModels()

                // Extract frameworks from models (convert enum to string)
                val frameworks = sdkModels
                    .flatMap { it.compatibleFrameworks.map { fw -> fw.toString() } }
                    .distinct()
                    .map { framework ->
                        FrameworkInfo(
                            name = framework,
                            description = "High-performance inference"
                        )
                    }

                // Convert SDK models to UI state
                val models = sdkModels.map { sdkModel ->
                    ModelItemState(
                        id = sdkModel.id,
                        name = sdkModel.name,
                        framework = sdkModel.preferredFramework?.toString() ?: sdkModel.compatibleFrameworks.firstOrNull()?.toString() ?: "Unknown",
                        sizeFormatted = formatBytes(sdkModel.memoryRequired ?: 0L),
                        format = sdkModel.format.name,
                        supportsThinking = sdkModel.supportsThinking,
                        isDownloaded = sdkModel.localPath != null,
                        isLoaded = false, // Would need to check current loaded model
                        isDownloading = false,
                        downloadProgress = 0f
                    )
                }

                _uiState.update {
                    it.copy(
                        frameworks = frameworks,
                        models = models
                    )
                }
            } catch (e: Exception) {
                // Handle error - show empty state
                _uiState.update {
                    it.copy(
                        frameworks = emptyList(),
                        models = emptyList()
                    )
                }
            }
        }
    }

    private fun formatBytes(bytes: Long): String {
        val gb = bytes / (1024.0 * 1024.0 * 1024.0)
        return if (gb >= 1.0) {
            String.format("%.2f GB", gb)
        } else {
            val mb = bytes / (1024.0 * 1024.0)
            String.format("%.0f MB", mb)
        }
    }

    fun toggleFramework(frameworkName: String) {
        _uiState.update {
            it.copy(
                expandedFramework = if (it.expandedFramework == frameworkName) null else frameworkName
            )
        }
    }

    fun downloadModel(modelId: String) {
        viewModelScope.launch {
            // TODO: Call SDK download with progress
            // com.runanywhere.sdk.public.extensions.downloadModel(modelId)

            // Update model state to downloading
            _uiState.update { state ->
                state.copy(
                    models = state.models.map {
                        if (it.id == modelId) it.copy(isDownloading = true, downloadProgress = 0f)
                        else it
                    }
                )
            }

            // Simulate download progress (replace with actual SDK progress)
            for (progress in 1..10) {
                kotlinx.coroutines.delay(500)
                _uiState.update { state ->
                    state.copy(
                        models = state.models.map {
                            if (it.id == modelId) it.copy(downloadProgress = progress / 10f)
                            else it
                        }
                    )
                }
            }

            // Mark as downloaded
            _uiState.update { state ->
                state.copy(
                    models = state.models.map {
                        if (it.id == modelId) it.copy(
                            isDownloading = false,
                            isDownloaded = true,
                            downloadProgress = 1f
                        )
                        else it
                    }
                )
            }
        }
    }

    fun loadModel(modelId: String) {
        viewModelScope.launch {
            // TODO: Call SDK to load model
            // com.runanywhere.sdk.public.extensions.loadModelWithInfo(modelInfo)

            // Unload any currently loaded model
            _uiState.update { state ->
                state.copy(
                    models = state.models.map { it.copy(isLoaded = it.id == modelId) }
                )
            }
        }
    }

    fun deleteModel(modelId: String) {
        viewModelScope.launch {
            // TODO: Call SDK to delete model
            // com.runanywhere.sdk.public.RunAnywhere.deleteModel(modelId)

            _uiState.update { state ->
                state.copy(
                    models = state.models.map {
                        if (it.id == modelId) it.copy(isDownloaded = false, isLoaded = false)
                        else it
                    }
                )
            }
        }
    }

    fun refreshModels() {
        loadFrameworksAndModels()
    }
}

/**
 * UI State for Models Screen
 */
data class ModelsUiState(
    val deviceInfo: DeviceInfo? = null,
    val frameworks: List<FrameworkInfo> = emptyList(),
    val models: List<ModelItemState> = emptyList(),
    val expandedFramework: String? = null,
    val isLoading: Boolean = false,
    val error: String? = null
) {
    fun getModelsForFramework(frameworkName: String): List<ModelItemState> {
        return models.filter { it.framework.equals(frameworkName, ignoreCase = true) }
    }
}


/**
 * Framework Information
 */
data class FrameworkInfo(
    val name: String,
    val description: String
)

/**
 * Model Item State
 */
data class ModelItemState(
    val id: String,
    val name: String,
    val framework: String,
    val sizeFormatted: String,
    val format: String,
    val supportsThinking: Boolean,
    val isDownloaded: Boolean,
    val isLoaded: Boolean,
    val isDownloading: Boolean,
    val downloadProgress: Float
)
