package com.runanywhere.runanywhereai.presentation.chat

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.RunAnywhereApplication
import com.runanywhere.runanywhereai.data.ConversationStore
import com.runanywhere.runanywhereai.domain.models.*
import com.runanywhere.sdk.public.RunAnywhere
// import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.util.*
import kotlin.collections.map
import kotlin.collections.toMutableList
import kotlin.math.ceil
// import javax.inject.Inject

/**
 * Enhanced ChatUiState matching iOS functionality
 */
data class ChatUiState(
    val messages: List<ChatMessage> = emptyList(),
    val isGenerating: Boolean = false,
    val isModelLoaded: Boolean = false,
    val loadedModelName: String? = null,
    val currentInput: String = "",
    val error: Throwable? = null,
    val useStreaming: Boolean = true,
    val currentConversation: Conversation? = null
) {
    val canSend: Boolean
        get() = currentInput.trim().isNotEmpty() && !isGenerating && isModelLoaded
}

/**
 * Enhanced ChatViewModel matching iOS ChatViewModel functionality
 * Includes streaming, thinking mode, analytics, and conversation management
 */
// @HiltViewModel
class ChatViewModel(application: Application) : AndroidViewModel(application) {

    private val app = application as RunAnywhereApplication
    private val conversationStore = ConversationStore.getInstance(application)
    private val tokensPerSecondHistory = mutableListOf<Double>()

    private val _uiState = MutableStateFlow(ChatUiState())
    val uiState: StateFlow<ChatUiState> = _uiState.asStateFlow()

    private var generationJob: Job? = null

    init {
        // Always start with a new conversation for a fresh chat experience
        val conversation = conversationStore.createConversation()
        _uiState.value = _uiState.value.copy(currentConversation = conversation)

        // Initialize with system message if model is already loaded
        viewModelScope.launch {
            checkModelStatus()
            // Add system message only if model is loaded
            if (_uiState.value.isModelLoaded) {
                addSystemMessage()
            }
        }
    }

    /**
     * Add system message
     */
    private fun addSystemMessage() {
        val modelName = _uiState.value.loadedModelName ?: return

        val content = "Model '$modelName' is loaded and ready to chat!"
        val systemMessage = ChatMessage(
            role = MessageRole.SYSTEM,
            content = content
        )

        val currentMessages = _uiState.value.messages.toMutableList()
        currentMessages.add(0, systemMessage)
        _uiState.value = _uiState.value.copy(messages = currentMessages)

        // Save to conversation store
        _uiState.value.currentConversation?.let { conversation ->
            val updatedConversation = conversation.copy(messages = currentMessages)
            conversationStore.updateConversation(updatedConversation)
        }
    }

    /**
     * Send message with streaming support and analytics
     * Matches iOS sendMessage functionality
     */
    fun sendMessage() {
        val currentState = _uiState.value

        Log.i("ChatViewModel", "🎯 sendMessage() called")
        Log.i(
            "ChatViewModel",
            "📝 canSend: ${currentState.canSend}, isModelLoaded: ${currentState.isModelLoaded}, loadedModelName: ${currentState.loadedModelName}"
        )

        if (!currentState.canSend) {
            Log.w("ChatViewModel", "Cannot send message - canSend is false")
            return
        }

        Log.i("ChatViewModel", "✅ canSend is true, proceeding")

        val prompt = currentState.currentInput
        Log.i("ChatViewModel", "🎯 Sending message: ${prompt.take(50)}...")

        // Clear input and set generating state
        _uiState.value = currentState.copy(
            currentInput = "",
            isGenerating = true,
            error = null
        )

        // Add user message
        val userMessage = ChatMessage(
            role = MessageRole.USER,
            content = prompt
        )

        _uiState.value = _uiState.value.copy(
            messages = _uiState.value.messages + userMessage
        )

        // Save user message to conversation
        _uiState.value.currentConversation?.let { conversation ->
            conversationStore.addMessage(userMessage, conversation)
        }

        // Create assistant message that will be updated with streaming tokens
        val assistantMessage = ChatMessage(
            role = MessageRole.ASSISTANT,
            content = ""
        )

        _uiState.value = _uiState.value.copy(
            messages = _uiState.value.messages + assistantMessage
        )

        // Start generation
        generationJob = viewModelScope.launch {
            try {
                if (currentState.useStreaming) {
                    generateWithStreaming(prompt, assistantMessage.id)
                } else {
                    generateWithoutStreaming(prompt, assistantMessage.id)
                }
            } catch (e: Exception) {
                handleGenerationError(e, assistantMessage.id)
            }
        }
    }

    /**
     * Generate with streaming support and thinking mode
     * Matches iOS streaming generation pattern
     */
    private suspend fun generateWithStreaming(prompt: String, messageId: String) {
        val startTime = System.currentTimeMillis()
        var firstTokenTime: Long? = null
        var thinkingStartTime: Long? = null
        var thinkingEndTime: Long? = null

        var fullResponse = ""
        var isInThinkingMode = false
        var thinkingContent = ""
        var responseContent = ""
        var totalTokensReceived = 0
        var wasInterrupted = false

        Log.i("ChatViewModel", "📤 Starting streaming generation")

        try {
            // Use KMP SDK streaming generation
            RunAnywhere.generateStream(prompt)
                .collect { token ->
                    fullResponse += token
                    totalTokensReceived++

                    // Track first token time
                    if (firstTokenTime == null) {
                        firstTokenTime = System.currentTimeMillis()
                    }

                    // Calculate real-time tokens per second
                    if (totalTokensReceived % 10 == 0) {
                        val elapsed = System.currentTimeMillis() - (firstTokenTime ?: startTime)
                        if (elapsed > 0) {
                            val currentSpeed = totalTokensReceived.toDouble() / (elapsed / 1000.0)
                            tokensPerSecondHistory.add(currentSpeed)
                        }
                    }

                    // Handle thinking mode
                    if (fullResponse.contains("<think>") && !isInThinkingMode) {
                        isInThinkingMode = true
                        thinkingStartTime = System.currentTimeMillis()
                        Log.i("ChatViewModel", "🧠 Entering thinking mode")
                    }

                    if (isInThinkingMode) {
                        if (fullResponse.contains("</think>")) {
                            // Extract thinking and response content
                            val thinkingRange = fullResponse.indexOf("<think>") + 7
                            val thinkingEndRange = fullResponse.indexOf("</think>")

                            if (thinkingRange < thinkingEndRange) {
                                thinkingContent = fullResponse.substring(thinkingRange, thinkingEndRange)
                                responseContent = fullResponse.substring(thinkingEndRange + 8)
                                isInThinkingMode = false
                                thinkingEndTime = System.currentTimeMillis()
                                Log.i("ChatViewModel", "🧠 Exiting thinking mode")
                            }
                        } else {
                            // Still in thinking mode
                            val thinkingRange = fullResponse.indexOf("<think>") + 7
                            if (thinkingRange < fullResponse.length) {
                                thinkingContent = fullResponse.substring(thinkingRange)
                            }
                        }
                    } else {
                        // Not in thinking mode, show response tokens directly
                        responseContent = fullResponse.replace("</think>", "").trim()
                    }

                    // Update the assistant message
                    updateAssistantMessage(
                        messageId = messageId,
                        content = if (isInThinkingMode) "" else responseContent,
                        thinkingContent = if (thinkingContent.isEmpty()) null else thinkingContent.trim()
                    )
                }

        } catch (e: Exception) {
            Log.e("ChatViewModel", "Streaming failed", e)
            wasInterrupted = true
            throw e
        }

        val endTime = System.currentTimeMillis()

        // Handle edge case: Stream ended while still in thinking mode
        if (isInThinkingMode && !fullResponse.contains("</think>")) {
            Log.w("ChatViewModel", "⚠️ Stream ended while in thinking mode")
            wasInterrupted = true

            if (thinkingContent.isNotEmpty()) {
                val remainingContent = fullResponse
                    .replace("<think>", "")
                    .replace(thinkingContent, "")
                    .trim()

                val intelligentResponse = if (remainingContent.isEmpty()) {
                    generateThinkingSummaryResponse(thinkingContent)
                } else remainingContent

                updateAssistantMessage(
                    messageId = messageId,
                    content = intelligentResponse,
                    thinkingContent = thinkingContent.trim()
                )
            }
        }

        // Create analytics
        val analytics = createMessageAnalytics(
            messageId = messageId,
            conversationId = _uiState.value.currentConversation?.id ?: "",
            startTime = startTime,
            endTime = endTime,
            firstTokenTime = firstTokenTime,
            thinkingStartTime = thinkingStartTime,
            thinkingEndTime = thinkingEndTime,
            inputText = prompt,
            outputText = responseContent,
            thinkingText = thinkingContent.takeIf { it.isNotEmpty() },
            tokensPerSecondHistory = tokensPerSecondHistory.toList(),
            wasInterrupted = wasInterrupted,
            generationMode = GenerationMode.STREAMING
        )

        // Update message with analytics
        updateAssistantMessageWithAnalytics(messageId, analytics)

        _uiState.value = _uiState.value.copy(isGenerating = false)
        Log.i("ChatViewModel", "✅ Streaming generation completed")
    }

    /**
     * Generate without streaming
     */
    private suspend fun generateWithoutStreaming(prompt: String, messageId: String) {
        val startTime = System.currentTimeMillis()

        try {
            val response = RunAnywhere.generate(prompt)
            val endTime = System.currentTimeMillis()

            updateAssistantMessage(messageId, response, null)

            val analytics = createMessageAnalytics(
                messageId = messageId,
                conversationId = _uiState.value.currentConversation?.id ?: "",
                startTime = startTime,
                endTime = endTime,
                firstTokenTime = null,
                thinkingStartTime = null,
                thinkingEndTime = null,
                inputText = prompt,
                outputText = response,
                thinkingText = null,
                tokensPerSecondHistory = emptyList(),
                wasInterrupted = false,
                generationMode = GenerationMode.NON_STREAMING
            )

            updateAssistantMessageWithAnalytics(messageId, analytics)

        } catch (e: Exception) {
            throw e
        } finally {
            _uiState.value = _uiState.value.copy(isGenerating = false)
        }
    }

    /**
     * Handle generation errors
     */
    private fun handleGenerationError(error: Exception, messageId: String) {
        Log.e("ChatViewModel", "❌ Generation failed", error)

        val errorMessage = when {
            !_uiState.value.isModelLoaded -> "❌ No model is loaded. Please select and load a model first."
            else -> "❌ Generation failed: ${error.message}"
        }

        updateAssistantMessage(messageId, errorMessage, null)

        _uiState.value = _uiState.value.copy(
            isGenerating = false,
            error = error
        )
    }

    /**
     * Update assistant message content
     */
    private fun updateAssistantMessage(messageId: String, content: String, thinkingContent: String?) {
        val currentMessages = _uiState.value.messages
        val updatedMessages = currentMessages.map { message ->
            if (message.id == messageId) {
                message.copy(
                    content = content,
                    thinkingContent = thinkingContent
                )
            } else {
                message
            }
        }

        _uiState.value = _uiState.value.copy(messages = updatedMessages)
    }

    /**
     * Update assistant message with analytics
     */
    private fun updateAssistantMessageWithAnalytics(messageId: String, analytics: MessageAnalytics) {
        val currentMessages = _uiState.value.messages
        val updatedMessages = currentMessages.map { message ->
            if (message.id == messageId) {
                message.copy(analytics = analytics)
            } else {
                message
            }
        }

        _uiState.value = _uiState.value.copy(messages = updatedMessages)
    }

    /**
     * Create comprehensive message analytics
     */
    private suspend fun createMessageAnalytics(
        messageId: String,
        conversationId: String,
        startTime: Long,
        endTime: Long,
        firstTokenTime: Long?,
        thinkingStartTime: Long?,
        thinkingEndTime: Long?,
        inputText: String,
        outputText: String,
        thinkingText: String?,
        tokensPerSecondHistory: List<Double>,
        wasInterrupted: Boolean,
        generationMode: GenerationMode
    ): MessageAnalytics {

        val totalGenerationTime = endTime - startTime
        val timeToFirstToken = firstTokenTime?.let { it - startTime }

        val thinkingTime = if (thinkingStartTime != null && thinkingEndTime != null) {
            thinkingEndTime - thinkingStartTime
        } else null

        val responseTime = thinkingTime?.let { totalGenerationTime - it }

        // Estimate token counts (simple approximation)
        val inputTokens = estimateTokenCount(inputText)
        val outputTokens = estimateTokenCount(outputText)
        val thinkingTokens = thinkingText?.let { estimateTokenCount(it) }
        val responseTokens = outputTokens - (thinkingTokens ?: 0)

        val averageTokensPerSecond = if (totalGenerationTime > 0) {
            outputTokens.toDouble() / (totalGenerationTime / 1000.0)
        } else 0.0

        val completionStatus = if (wasInterrupted) {
            CompletionStatus.INTERRUPTED
        } else {
            CompletionStatus.COMPLETE
        }

        return MessageAnalytics(
            messageId = messageId,
            conversationId = conversationId,
            modelId = _uiState.value.loadedModelName ?: "unknown",
            modelName = _uiState.value.loadedModelName ?: "Unknown",
            framework = "KMP",
            timestamp = startTime,
            timeToFirstToken = timeToFirstToken,
            totalGenerationTime = totalGenerationTime,
            thinkingTime = thinkingTime,
            responseTime = responseTime,
            inputTokens = inputTokens,
            outputTokens = outputTokens,
            thinkingTokens = thinkingTokens,
            responseTokens = responseTokens,
            averageTokensPerSecond = averageTokensPerSecond,
            messageLength = outputText.length,
            wasThinkingMode = thinkingText != null,
            wasInterrupted = wasInterrupted,
            retryCount = 0,
            completionStatus = completionStatus,
            tokensPerSecondHistory = tokensPerSecondHistory,
            generationMode = generationMode,
            contextWindowUsage = 0.0,
            generationParameters = GenerationParameters()
        )
    }

    /**
     * Simple token estimation (approximately 4 characters per token)
     */
    private fun estimateTokenCount(text: String): Int {
        return ceil(text.length / 4.0).toInt()
    }

    /**
     * Generate intelligent response from thinking content
     */
    private fun generateThinkingSummaryResponse(thinkingContent: String): String {
        val thinking = thinkingContent.trim()

        return when {
            thinking.lowercase().contains("user") && thinking.lowercase().contains("help") ->
                "I'm here to help! Let me know what you need."
            thinking.lowercase().contains("question") || thinking.lowercase().contains("ask") ->
                "That's a good question. Let me think about this more."
            thinking.lowercase().contains("consider") || thinking.lowercase().contains("think") ->
                "Let me consider this carefully. How can I help you further?"
            thinking.length > 200 ->
                "I was thinking through this carefully. Could you help me understand what you're looking for?"
            else ->
                "I'm processing your message. What would be most helpful for you?"
        }
    }

    /**
     * Update current input text
     */
    fun updateInput(input: String) {
        _uiState.value = _uiState.value.copy(currentInput = input)
    }

    /**
     * Clear chat messages
     */
    fun clearChat() {
        generationJob?.cancel()

        val currentMessages = _uiState.value.messages
        _uiState.value = _uiState.value.copy(
            messages = emptyList(),
            currentInput = "",
            isGenerating = false,
            error = null
        )

        // Create new conversation
        val conversation = conversationStore.createConversation()
        _uiState.value = _uiState.value.copy(currentConversation = conversation)

        // Only add system message if model is loaded
        if (_uiState.value.isModelLoaded) {
            addSystemMessage()
        }
    }

    /**
     * Stop current generation
     */
    fun stopGeneration() {
        generationJob?.cancel()
        _uiState.value = _uiState.value.copy(isGenerating = false)
    }

    /**
     * Check model status
     */
    suspend fun checkModelStatus() {
        try {
            if (app.isSDKReady()) {
                val availableModels = RunAnywhere.availableModels()
                val loadedModel = availableModels.firstOrNull { it.localPath != null }

                _uiState.value = _uiState.value.copy(
                    isModelLoaded = loadedModel != null,
                    loadedModelName = loadedModel?.name
                )

                Log.i("ChatViewModel", "✅ Model status updated: '${loadedModel?.name}' is loaded")

                // Update system message to reflect current state
                val currentMessages = _uiState.value.messages.toMutableList()
                if (currentMessages.firstOrNull()?.role == MessageRole.SYSTEM) {
                    currentMessages.removeAt(0)
                }
                _uiState.value = _uiState.value.copy(messages = currentMessages)

                if (_uiState.value.isModelLoaded) {
                    addSystemMessage()
                }
            } else {
                _uiState.value = _uiState.value.copy(
                    isModelLoaded = false,
                    loadedModelName = null
                )
                Log.i("ChatViewModel", "❌ SDK not ready")
            }
        } catch (e: Exception) {
            Log.e("ChatViewModel", "Failed to check model status", e)
            _uiState.value = _uiState.value.copy(
                isModelLoaded = false,
                loadedModelName = null
            )
        }
    }

    /**
     * Load a conversation
     */
    fun loadConversation(conversation: Conversation) {
        _uiState.value = _uiState.value.copy(currentConversation = conversation)

        // For new conversations (empty messages), start fresh
        // For existing conversations, load the messages
        if (conversation.messages.isEmpty()) {
            _uiState.value = _uiState.value.copy(messages = emptyList())
            // Add system message if model is loaded
            if (_uiState.value.isModelLoaded) {
                addSystemMessage()
            }
        } else {
            _uiState.value = _uiState.value.copy(messages = conversation.messages)

            val analyticsCount = conversation.messages.mapNotNull { it.analytics }.size
            Log.i(
                "ChatViewModel",
                "📂 Loaded conversation with ${conversation.messages.size} messages, $analyticsCount have analytics"
            )
        }

        // Update model info if available
        conversation.modelName?.let { modelName ->
            _uiState.value = _uiState.value.copy(loadedModelName = modelName)
        }
    }

    /**
     * Create a new conversation
     */
    fun createNewConversation() {
        clearChat()
    }

    /**
     * Clear error state
     */
    fun clearError() {
        _uiState.value = _uiState.value.copy(error = null)
    }
}
