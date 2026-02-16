package com.runanywhere.runanywhereai.presentation.diffusion

import android.graphics.Bitmap
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionModelVariant
import com.runanywhere.sdk.public.extensions.cancelImageGeneration
import com.runanywhere.sdk.public.extensions.generateImage
import com.runanywhere.sdk.public.extensions.isDiffusionModelLoaded
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.nio.ByteBuffer

data class DiffusionUiState(
    val isModelLoaded: Boolean = false,
    val loadedModelName: String? = null,
    val isGenerating: Boolean = false,
    val generatedImage: Bitmap? = null,
    val prompt: String = "A beautiful sunset over mountains, oil painting style",
    val generationTimeMs: Long = 0,
    val errorMessage: String? = null,
)

/**
 * ViewModel for diffusion image generation.
 *
 * Model selection, download, and loading is handled by ModelSelectionBottomSheet
 * (same as LLM/STT/TTS). This ViewModel only handles generation.
 */
class DiffusionViewModel : ViewModel() {
    companion object {
        private const val TAG = "DiffusionVM"
    }

    private val _uiState = MutableStateFlow(DiffusionUiState())
    val uiState: StateFlow<DiffusionUiState> = _uiState.asStateFlow()

    init {
        checkModelStatus()
    }

    fun checkModelStatus() {
        _uiState.value = _uiState.value.copy(
            isModelLoaded = RunAnywhere.isDiffusionModelLoaded,
        )
    }

    fun onModelSelected(modelName: String) {
        _uiState.value = _uiState.value.copy(
            isModelLoaded = true,
            loadedModelName = modelName,
            errorMessage = null,
        )
    }

    fun updatePrompt(newPrompt: String) {
        _uiState.value = _uiState.value.copy(prompt = newPrompt)
    }

    fun generateImage() {
        val prompt = _uiState.value.prompt
        if (prompt.isBlank()) {
            _uiState.value = _uiState.value.copy(errorMessage = "Enter a prompt")
            return
        }

        viewModelScope.launch(Dispatchers.IO) {
            _uiState.value = _uiState.value.copy(
                isGenerating = true,
                errorMessage = null,
                generatedImage = null,
            )

            try {
                val options = DiffusionGenerationOptions.withVariantDefaults(
                    prompt = prompt,
                    variant = DiffusionModelVariant.SD_1_5,
                )

                val result = RunAnywhere.generateImage(prompt, options)

                val bitmap = Bitmap.createBitmap(result.width, result.height, Bitmap.Config.ARGB_8888)
                bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(result.imageData))

                _uiState.value = _uiState.value.copy(
                    isGenerating = false,
                    generatedImage = bitmap,
                    generationTimeMs = result.generationTimeMs,
                )
                Log.i(TAG, "Image generated: ${result.width}x${result.height} in ${result.generationTimeMs}ms")
            } catch (e: Exception) {
                Log.e(TAG, "Generation failed", e)
                _uiState.value = _uiState.value.copy(
                    isGenerating = false,
                    errorMessage = "Generation failed: ${e.message}",
                )
            }
        }
    }

    fun cancelGeneration() {
        RunAnywhere.cancelImageGeneration()
    }
}
