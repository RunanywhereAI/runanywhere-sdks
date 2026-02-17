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

data class GenerationRecord(
    val prompt: String,
    val image: Bitmap,
    val generationTimeMs: Long,
    val width: Int,
    val height: Int,
)

data class DiffusionUiState(
    val isModelLoaded: Boolean = false,
    val loadedModelName: String? = null,
    val isGenerating: Boolean = false,
    val generatedImage: Bitmap? = null,
    val prompt: String = "",
    val generationTimeMs: Long = 0,
    val errorMessage: String? = null,
    val generationHistory: List<GenerationRecord> = emptyList(),
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

        val samplePrompts = listOf(
            "A serene mountain landscape at sunset with golden light",
            "A futuristic city with flying cars and neon lights",
            "A cute corgi puppy wearing a tiny astronaut helmet",
            "An ancient library filled with magical floating books",
            "A cozy coffee shop on a rainy day, warm lighting",
        )
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
            )

            try {
                val options = DiffusionGenerationOptions.withVariantDefaults(
                    prompt = prompt,
                    variant = DiffusionModelVariant.SD_1_5,
                )

                val result = RunAnywhere.generateImage(prompt, options)

                val bitmap = Bitmap.createBitmap(result.width, result.height, Bitmap.Config.ARGB_8888)
                bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(result.imageData))

                val record = GenerationRecord(
                    prompt = prompt,
                    image = bitmap,
                    generationTimeMs = result.generationTimeMs,
                    width = result.width,
                    height = result.height,
                )

                _uiState.value = _uiState.value.copy(
                    isGenerating = false,
                    generatedImage = bitmap,
                    generationTimeMs = result.generationTimeMs,
                    generationHistory = _uiState.value.generationHistory + record,
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
