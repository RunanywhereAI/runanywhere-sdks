package com.runanywhere.runanywhereai.presentation.vision

import android.app.Application
import android.net.Uri
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VLM.VLMGenerationOptions
import com.runanywhere.sdk.public.extensions.VLM.VLMImage
import com.runanywhere.sdk.public.extensions.cancelVLMGeneration
import com.runanywhere.sdk.public.extensions.isVLMModelLoaded
import com.runanywhere.sdk.public.extensions.processImageStream
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

/**
 * UI state for VLM screen.
 * Mirrors iOS VLMViewModel published properties.
 */
data class VLMUiState(
    val isModelLoaded: Boolean = false,
    val loadedModelName: String? = null,
    val isProcessing: Boolean = false,
    val currentDescription: String = "",
    val error: String? = null,
    val selectedImageUri: Uri? = null,
    val showModelSelection: Boolean = false,
)

/**
 * VLM ViewModel matching iOS VLMViewModel functionality.
 *
 * Manages:
 * - VLM model status
 * - Image selection (from gallery)
 * - Image processing with streaming output
 * - Generation cancellation
 *
 * iOS Reference: examples/ios/RunAnywhereAI/.../Features/Vision/VLMViewModel.swift
 */
class VLMViewModel(application: Application) : AndroidViewModel(application) {
    companion object {
        private const val TAG = "VLMViewModel"
    }

    private val app = application as RunAnywhereApplication

    private val _uiState = MutableStateFlow(VLMUiState())
    val uiState: StateFlow<VLMUiState> = _uiState.asStateFlow()

    private var generationJob: Job? = null

    init {
        viewModelScope.launch {
            checkModelStatus()
        }
    }

    /**
     * Check if a VLM model is currently loaded.
     * Mirrors iOS checkModelStatus().
     */
    fun checkModelStatus() {
        try {
            val isLoaded = RunAnywhere.isVLMModelLoaded
            _uiState.update {
                it.copy(isModelLoaded = isLoaded)
            }
            Log.d(TAG, "VLM model loaded: $isLoaded")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check VLM model status: ${e.message}", e)
            _uiState.update {
                it.copy(isModelLoaded = false)
            }
        }
    }

    /**
     * Set selected image URI from photo picker.
     */
    fun setSelectedImage(uri: Uri?) {
        _uiState.update {
            it.copy(
                selectedImageUri = uri,
                currentDescription = "",
                error = null,
            )
        }
    }

    /**
     * Process the selected image with VLM.
     * Mirrors iOS describeImage() with streaming.
     *
     * @param prompt The text prompt to use
     */
    fun processSelectedImage(prompt: String = "Describe this image in detail.") {
        val uri = _uiState.value.selectedImageUri ?: return

        if (!_uiState.value.isModelLoaded) {
            _uiState.update { it.copy(error = "No VLM model loaded. Please select a model first.") }
            return
        }

        // Cancel any ongoing generation
        generationJob?.cancel()
        cancelGeneration()

        _uiState.update {
            it.copy(
                isProcessing = true,
                currentDescription = "",
                error = null,
            )
        }

        generationJob = viewModelScope.launch {
            try {
                // Copy image to a temp file so VLM can access it by path
                val tempFile = copyUriToTempFile(uri) ?: throw Exception("Failed to read image")
                val image = VLMImage.fromFilePath(tempFile.absolutePath)

                val options = VLMGenerationOptions(
                    maxTokens = 300,
                    temperature = 0.7f,
                )

                Log.i(TAG, "Starting VLM streaming for image: ${tempFile.name}")

                RunAnywhere.processImageStream(image, prompt, options)
                    .collect { token ->
                        _uiState.update {
                            it.copy(currentDescription = it.currentDescription + token)
                        }
                    }

                Log.i(TAG, "VLM streaming completed")
                _uiState.update { it.copy(isProcessing = false) }

                // Clean up temp file
                tempFile.delete()
            } catch (e: Exception) {
                Log.e(TAG, "VLM processing failed: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isProcessing = false,
                        error = "Processing failed: ${e.message}",
                    )
                }
            }
        }
    }

    /**
     * Cancel ongoing VLM generation.
     * Mirrors iOS cancelVLMGeneration().
     */
    fun cancelGeneration() {
        try {
            RunAnywhere.cancelVLMGeneration()
            generationJob?.cancel()
            _uiState.update { it.copy(isProcessing = false) }
            Log.d(TAG, "VLM generation cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel VLM generation: ${e.message}", e)
        }
    }

    /**
     * Show/hide model selection sheet.
     */
    fun setShowModelSelection(show: Boolean) {
        _uiState.update { it.copy(showModelSelection = show) }
    }

    /**
     * Called when a model is loaded via model selection sheet.
     */
    fun onModelLoaded(modelName: String) {
        _uiState.update {
            it.copy(
                isModelLoaded = true,
                loadedModelName = modelName,
                showModelSelection = false,
            )
        }
    }

    /**
     * Clear the current description and error.
     */
    fun clearResults() {
        _uiState.update {
            it.copy(
                currentDescription = "",
                error = null,
            )
        }
    }

    /**
     * Copy a content URI to a temporary file for VLM processing.
     */
    private fun copyUriToTempFile(uri: Uri): File? {
        return try {
            val context = getApplication<Application>()
            val inputStream = context.contentResolver.openInputStream(uri) ?: return null
            val tempFile = File.createTempFile("vlm_image_", ".jpg", context.cacheDir)
            FileOutputStream(tempFile).use { output ->
                inputStream.copyTo(output)
            }
            inputStream.close()
            tempFile
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy URI to temp file: ${e.message}", e)
            null
        }
    }

    override fun onCleared() {
        super.onCleared()
        generationJob?.cancel()
    }
}
