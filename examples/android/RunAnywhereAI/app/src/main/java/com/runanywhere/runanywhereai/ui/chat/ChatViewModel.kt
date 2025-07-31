package com.runanywhere.runanywhereai.ui.chat

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.repository.ModelRepository
import com.runanywhere.runanywhereai.llm.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * ViewModel for the chat screen
 */
class ChatViewModel(application: Application) : AndroidViewModel(application) {

    private val llmManager = UnifiedLLMManager(application)
    private val modelRepository = ModelRepository(application)

    private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    private val _currentModel = MutableStateFlow<com.runanywhere.runanywhereai.data.repository.ModelInfo?>(null)
    val currentModel: StateFlow<com.runanywhere.runanywhereai.data.repository.ModelInfo?> = _currentModel.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _generationOptions = MutableStateFlow(GenerationOptions())
    val generationOptions: StateFlow<GenerationOptions> = _generationOptions.asStateFlow()

    init {
        // Initialize with a default model if available
        viewModelScope.launch {
            loadDefaultModel()
        }
    }

    /**
     * Load the default model
     */
    private suspend fun loadDefaultModel() {
        try {
            val downloadedModels = modelRepository.getDownloadedModels()
            if (downloadedModels.isNotEmpty()) {
                val model = downloadedModels.first()
                selectModel(model)
            }
        } catch (e: Exception) {
            _error.value = "Failed to load default model: ${e.message}"
        }
    }

    /**
     * Select and load a model
     */
    suspend fun selectModel(modelInfo: com.runanywhere.runanywhereai.data.repository.ModelInfo) {
        try {
            _error.value = null

            val modelPath = modelInfo.localPath ?: modelRepository.getModelPath(modelInfo.fileName)
            llmManager.selectFramework(modelInfo.framework, modelPath)

            _currentModel.value = modelInfo
        } catch (e: Exception) {
            _error.value = "Failed to load model: ${e.message}"
            throw e
        }
    }

    /**
     * Send a message and generate response
     */
    fun sendMessage(content: String) {
        if (content.isBlank() || _isGenerating.value) return

        viewModelScope.launch {
            // Add user message
            _messages.value += ChatMessage(
                role = ChatRole.USER,
                content = content,
                timestamp = System.currentTimeMillis()
            )

            _isGenerating.value = true
            _error.value = null

            // Create assistant message placeholder
            val assistantMessage = ChatMessage(
                role = ChatRole.ASSISTANT,
                content = "",
                timestamp = System.currentTimeMillis()
            )
            _messages.value += assistantMessage

            try {
                // Check if model is loaded
                if (!llmManager.isInitialized()) {
                    throw IllegalStateException("No model loaded. Please select a model first.")
                }

                // Stream generation
                llmManager.generateStream(content, _generationOptions.value).collect { token ->
                    _messages.value = _messages.value.map { msg ->
                        if (msg == assistantMessage) {
                            msg.copy(content = msg.content + token)
                        } else msg
                    }
                }
            } catch (e: Exception) {
                _messages.value = _messages.value.map { msg ->
                    if (msg == assistantMessage) {
                        msg.copy(content = "Error: ${e.message}")
                    } else msg
                }
                _error.value = e.message
            } finally {
                _isGenerating.value = false
            }
        }
    }

    /**
     * Clear chat history
     */
    fun clearChat() {
        _messages.value = emptyList()
        _error.value = null
    }

    /**
     * Update generation options
     */
    fun updateGenerationOptions(options: GenerationOptions) {
        _generationOptions.value = options
    }

    /**
     * Get current model info from LLM manager
     */
    fun getLLMModelInfo(): com.runanywhere.runanywhereai.llm.ModelInfo? {
        return llmManager.getModelInfo()
    }

    override fun onCleared() {
        super.onCleared()
        // Launch coroutine for suspend function
        viewModelScope.launch {
            llmManager.release()
        }
    }
}
