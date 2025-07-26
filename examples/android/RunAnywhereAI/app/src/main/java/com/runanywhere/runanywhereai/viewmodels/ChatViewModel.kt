package com.runanywhere.runanywhereai.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.models.Conversation
import com.runanywhere.runanywhereai.data.models.Message
import com.runanywhere.runanywhereai.data.repository.ConversationRepository
import com.runanywhere.runanywhereai.llm.GenerationOptions
import com.runanywhere.runanywhereai.llm.LLMFramework
import com.runanywhere.runanywhereai.llm.ModelInfo
import com.runanywhere.runanywhereai.llm.UnifiedLLMManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ChatViewModel @Inject constructor(
    private val conversationRepository: ConversationRepository,
    private val llmManager: UnifiedLLMManager
) : ViewModel() {
    
    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()
    
    private val _messages = MutableStateFlow<List<Message>>(emptyList())
    val messages: StateFlow<List<Message>> = _messages.asStateFlow()
    
    private var currentConversationId: String? = null
    
    fun loadConversation(conversationId: String) {
        viewModelScope.launch {
            currentConversationId = conversationId
            
            // Load conversation messages
            conversationRepository.getConversationMessages(conversationId)
                .collectLatest { messages ->
                    _messages.value = messages
                }
        }
    }
    
    fun createNewConversation(framework: LLMFramework, modelName: String) {
        viewModelScope.launch {
            val conversation = conversationRepository.createConversation(
                title = "New Conversation",
                framework = framework.name,
                modelName = modelName
            )
            currentConversationId = conversation.id
            _uiState.update { it.copy(conversation = conversation) }
        }
    }
    
    fun sendMessage() {
        val input = _uiState.value.currentInput
        if (input.isBlank()) return
        
        viewModelScope.launch {
            val conversationId = currentConversationId ?: return@launch
            
            // Add user message
            conversationRepository.addMessage(
                conversationId = conversationId,
                role = "user",
                content = input,
                tokenCount = input.split(" ").size // Simple token count
            )
            
            // Clear input and start generation
            _uiState.update { 
                it.copy(
                    currentInput = "",
                    isGenerating = true
                )
            }
            
            try {
                // Generate response
                val options = GenerationOptions(
                    maxTokens = 500,
                    temperature = 0.7f
                )
                
                val result = llmManager.generate(input, options)
                
                // Add assistant message
                conversationRepository.addMessage(
                    conversationId = conversationId,
                    role = "assistant",
                    content = result.text,
                    tokenCount = result.tokensGenerated,
                    generationTimeMs = result.timeMs
                )
            } catch (e: Exception) {
                // Handle error
                _uiState.update { 
                    it.copy(
                        error = e.message,
                        isGenerating = false
                    )
                }
            } finally {
                _uiState.update { it.copy(isGenerating = false) }
            }
        }
    }
    
    fun updateInput(input: String) {
        _uiState.update { it.copy(currentInput = input) }
    }
    
    fun selectModel(framework: LLMFramework, modelPath: String) {
        viewModelScope.launch {
            try {
                llmManager.selectFramework(framework, modelPath)
                val modelInfo = llmManager.getModelInfo()
                _uiState.update { 
                    it.copy(
                        currentModel = modelInfo,
                        currentFramework = framework
                    )
                }
            } catch (e: Exception) {
                _uiState.update { 
                    it.copy(error = e.message)
                }
            }
        }
    }
    
    fun clearConversation() {
        viewModelScope.launch {
            currentConversationId?.let { id ->
                conversationRepository.deleteConversation(id)
                currentConversationId = null
                _messages.value = emptyList()
                _uiState.update { it.copy(conversation = null) }
            }
        }
    }
    
    fun exportConversation() {
        viewModelScope.launch {
            currentConversationId?.let { id ->
                val exportData = conversationRepository.exportConversation(id)
                // TODO: Handle export (share intent, save to file, etc.)
            }
        }
    }
    
    fun showConversationInfo() {
        // TODO: Show conversation info dialog
    }
    
    fun showSettings() {
        // TODO: Navigate to settings
    }
    
    fun editMessage(messageId: String) {
        // TODO: Implement message editing
    }
    
    fun regenerateResponse(messageId: String) {
        // TODO: Implement response regeneration
    }
    
    fun branchConversation(messageId: String) {
        // TODO: Implement conversation branching
    }
    
    fun attachImage() {
        // TODO: Implement image attachment
    }
}

data class ChatUiState(
    val conversation: Conversation? = null,
    val currentInput: String = "",
    val isGenerating: Boolean = false,
    val error: String? = null,
    val currentModel: ModelInfo? = null,
    val currentFramework: LLMFramework? = null,
    val showModelSelector: Boolean = true
)