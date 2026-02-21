package com.runanywhere.run_anywhere_lora

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelRegistry
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LLMGenerationOptions
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.clearLoraAdapters
import com.runanywhere.sdk.public.extensions.generateStreamWithMetrics
import com.runanywhere.sdk.public.extensions.getLoadedLoraAdapters
import com.runanywhere.sdk.public.extensions.isLLMModelLoaded
import com.runanywhere.sdk.public.extensions.loadLLMModel
import com.runanywhere.sdk.public.extensions.loadLoraAdapter
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.extensions.removeLoraAdapter
import com.runanywhere.sdk.public.extensions.unloadLLMModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class GenerationMetrics(
    val tokensPerSecond: Double,
    val totalTokens: Int,
    val latencyMs: Double,
)

data class LoraUiState(
    val modelPath: String? = null,
    val modelLoaded: Boolean = false,
    val modelLoading: Boolean = false,
    val loraAdapters: List<LoRAAdapterInfo> = emptyList(),
    val question: String = "",
    val answer: String = "",
    val isGenerating: Boolean = false,
    val metrics: GenerationMetrics? = null,
    val error: String? = null,
)

class LoraViewModel : ViewModel() {

    companion object {
        private const val TAG = "LoraVM"
    }

    private val _uiState = MutableStateFlow(LoraUiState())
    val uiState: StateFlow<LoraUiState> = _uiState.asStateFlow()

    private var generationJob: Job? = null

    fun updateQuestion(text: String) {
        _uiState.update { it.copy(question = text) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun loadModel(path: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(modelLoading = true, error = null) }
            try {
                // Unload existing model if loaded
                if (RunAnywhere.isLLMModelLoaded()) {
                    RunAnywhere.unloadLLMModel()
                }

                // Generate a model ID from filename
                val filename = path.substringAfterLast('/')
                val modelId = filename.removeSuffix(".gguf")

                // Register the model in the SDK registry
                RunAnywhere.registerModel(
                    id = modelId,
                    name = filename,
                    url = "file://$path",
                    framework = InferenceFramework.LLAMA_CPP,
                )

                // Tell the C++ registry the file is already local at this path
                CppBridgeModelRegistry.updateDownloadStatus(modelId, path)

                // Load the model
                withContext(Dispatchers.IO) {
                    RunAnywhere.loadLLMModel(modelId)
                }

                _uiState.update {
                    it.copy(
                        modelPath = path,
                        modelLoaded = true,
                        modelLoading = false,
                        loraAdapters = emptyList(),
                    )
                }
                Log.i(TAG, "Model loaded: $filename")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load model: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        modelLoading = false,
                        error = "Failed to load model: ${e.message}",
                    )
                }
            }
        }
    }

    fun loadLoraAdapter(path: String, scale: Float) {
        viewModelScope.launch {
            _uiState.update { it.copy(error = null) }
            try {
                withContext(Dispatchers.IO) {
                    RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path = path, scale = scale))
                }
                refreshAdapters()
                Log.i(TAG, "LoRA adapter loaded: ${path.substringAfterLast('/')} (scale=$scale)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load LoRA adapter: ${e.message}", e)
                _uiState.update { it.copy(error = "Failed to load LoRA: ${e.message}") }
            }
        }
    }

    fun removeLoraAdapter(path: String) {
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    RunAnywhere.removeLoraAdapter(path)
                }
                refreshAdapters()
            } catch (e: Exception) {
                _uiState.update { it.copy(error = "Failed to remove LoRA: ${e.message}") }
            }
        }
    }

    fun clearLoraAdapters() {
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    RunAnywhere.clearLoraAdapters()
                }
                _uiState.update { it.copy(loraAdapters = emptyList()) }
            } catch (e: Exception) {
                _uiState.update { it.copy(error = "Failed to clear LoRA: ${e.message}") }
            }
        }
    }

    fun askQuestion() {
        val question = _uiState.value.question.trim()
        if (question.isEmpty()) return
        if (!_uiState.value.modelLoaded) {
            _uiState.update { it.copy(error = "Load a model first") }
            return
        }

        generationJob?.cancel()
        generationJob = viewModelScope.launch {
            _uiState.update {
                it.copy(
                    answer = "",
                    isGenerating = true,
                    metrics = null,
                    error = null,
                )
            }

            try {
                val result = withContext(Dispatchers.IO) {
                    RunAnywhere.generateStreamWithMetrics(
                        prompt = question,
                        options = LLMGenerationOptions(
                            maxTokens = 1024,
                            temperature = 0.7f,
                        ),
                    )
                }

                // Collect streaming tokens
                result.stream.collect { token ->
                    _uiState.update { it.copy(answer = it.answer + token) }
                }

                // Get final metrics
                val finalResult = result.result.await()
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        metrics = GenerationMetrics(
                            tokensPerSecond = finalResult.tokensPerSecond,
                            totalTokens = finalResult.tokensUsed,
                            latencyMs = finalResult.latencyMs,
                        ),
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Generation failed: ${e.message}", e)
                _uiState.update {
                    it.copy(
                        isGenerating = false,
                        error = "Generation failed: ${e.message}",
                    )
                }
            }
        }
    }

    fun cancelGeneration() {
        generationJob?.cancel()
        RunAnywhere.cancelGeneration()
        _uiState.update { it.copy(isGenerating = false) }
    }

    private suspend fun refreshAdapters() {
        try {
            val adapters = withContext(Dispatchers.IO) {
                RunAnywhere.getLoadedLoraAdapters()
            }
            _uiState.update { it.copy(loraAdapters = adapters) }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to refresh adapters: ${e.message}", e)
        }
    }
}
